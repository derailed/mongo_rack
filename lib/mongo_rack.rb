require 'rack/session/abstract/id'
require 'mongo'
require File.join( File.dirname(__FILE__), %w[mongo_rack session_hash.rb] )
require File.join( File.dirname(__FILE__), %w[core_ext hash.rb] )
require 'yaml'
require 'logger'

module Rack  
  module Session    
    class Mongo < Abstract::ID      
      attr_reader :mutex, :connection, :db, :sessions #:nodoc:
      
      # === Options for mongo_rack
      # :server :: 
      #   Specifies server, port, db and collection location. Defaults
      #   to localhost:27017/mongo_session/sessions. Format must conform to
      #   the format {host}:{port}/{database_name}/{collection_name}.
      # :pool_size :: 
      #   The connection socket pool size - see mongo-ruby-driver docs for settings.
      #   Defaults to 1 connection.
      # :pool_timeout :: 
      #   The connection pool timeout. see mongo-ruby-driver docs for settings.
      #   Defaults to 1 sec.
      # :logging ::
      #   Set to true to enable logger. Default is false
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge \
        :server       => 'localhost:27017/mongo_session/sessions',
        :pool_size    => 1,
        :pool_timeout => 1.0,
        :log_level    => :fatal

      # Initializes mongo_rack. Pass in options for default override.
      def initialize(app, options={})
        super

        host, port, db_name, cltn_name = parse_server_desc( @default_options[:server] )
        
        @mutex      = Mutex.new      
        @connection = ::Mongo::Connection.new( 
          host, 
          port,
          :pool_size => @default_options[:pool_size],
          :timeout   => @default_options[:pool_timeout] )
        @db         = @connection.db( db_name )
        @sessions   = @db[cltn_name]

        @logger = Logger.new( $stdout )
        @logger.level = set_log_level( @default_options[:log_level] )
      end
      
      # Fetch session with optional session id. Retrieve session from mongodb if any    
      def get_session( env, sid )
        return _get_session( env, sid ) unless env['rack.multithread']
        mutex.synchronize do
          return _get_session( env, sid )
        end        
      end

      # Update session params and sync to mongoDB.
      def set_session( env, sid, new_session, options )
        return _set_session( env, sid, new_session, options ) unless env['rack.multithread']
        mutex.synchronize do    
          return _set_session( env, sid, new_session, options )
        end        
      end
                        
      # =======================================================================
      private

        # Generates unique session id
        def generate_sid
          loop do          
            sid = super
            break sid unless sessions.find_one( { :_id => sid } )
          end
        end

        # Check session expiration date
        def fresh?( ses_obj )
          return true if ses_obj['expire'] == 0
          now = Time.now
          ses_obj['expire'] >= now        
        end
      
        # Clean out all expired sessions
        def clean_expired!
          sessions.remove( { :expire => { '$lt' => Time.now } } )
        end

        # parse server description string into host, port, db, cltn
        def parse_server_desc( desc )
          tokens = desc.split( "/" )
          raise "Invalid server description" unless tokens.size == 3
          server_desc = tokens[0].split( ":" )
          raise "Invalid host:port description" unless server_desc.size == 2        
          return server_desc.first, server_desc.last.to_i, tokens[1], tokens[2]
        end
        
        # Use YAML to store session objects
        def serialize( ses )
          YAML::dump( ses )
        end
        
        # Session object stored in YAML
        def deserialize( buff )
          YAML::load( buff )
        end
        
        # fetch session with optional session id
        def _get_session(env, sid)
          logger.debug "Getting session info for #{sid.inspect}"
          if sid
            ses_obj = sessions.find_one( { :_id => sid } )
            if ses_obj                       
              logger.debug "Found session object on #{sid.inspect}"
            else
              logger.debug "Unable to find session object #{sid.inspect}"
            end
            session = MongoRack::SessionHash.new( deserialize(ses_obj['data']) ) if ses_obj and fresh?( ses_obj )
          end
    
          unless sid and session
            logger.warn "Session ID not found - #{sid.inspect} - Creating new session"
            session = MongoRack::SessionHash.new
            sid     = generate_sid
            ret     = sessions.save( { :_id => sid, :data => serialize(session) } )
            raise "Session collision on '#{sid.inspect}'" unless ret
          end
          merged = MongoRack::SessionHash.new.merge(session)
          logger.debug "Setting old session #{merged.inspect}"          
          session.instance_variable_set( '@old', merged )
          return [sid, session]
        rescue => boom          
          logger.error "#{self} Hoy! something bad happened loading session data"
          logger.error $!.inspect
          boom.backtrace.each{ |l| logger.error l }          
          return [ nil, MongoRack::SessionHash.new ]
        end
            
        # update session information with new settings
        def _set_session(env, sid, new_session, options)
          logger.debug "Setting session #{new_session.inspect}"          
          ses_obj = sessions.find_one( { :_id => sid } )
          if ses_obj
            logger.debug "Found existing session for -- #{sid.inspect}"
            session = MongoRack::SessionHash.new( deserialize( ses_obj['data'] ) )
          else
            logger.debug "Unable to find session for -- #{sid.inspect}"
            session = MongoRack::SessionHash.new
          end
    
          if options[:renew] or options[:drop]
            sessions.remove( { :_id => sid } )
            return false if options[:drop]
            sid = generate_sid
            sessions.insert( {:_id => sid, :data => {} } )
          end
          old_session = new_session.instance_variable_get('@old') || MongoRack::SessionHash.new
          logger.debug "Setting old session -- #{old_session.inspect}"          
          merged = merge_sessions( sid, old_session, new_session, session )

          expiry = options[:expire_after]
          expiry = expiry ? Time.now + options[:expire_after] : 0

          # BOZO ! Use upserts here if minor changes ?
          logger.debug "Updating session -- #{merged.inspect}"          
          sessions.save( { :_id => sid, :data => serialize( merged ), :expire => expiry } )
          return sid
        rescue => boom      
          logger.error "#{self} Hoy! Something went wrong. Unable to persist session."
          logger.error $!.inspect
          boom.backtrace.each{ |l| logger.error l }
          return false
        end

        # merge old, new to current session state
        def merge_sessions( sid, old_s, new_s, cur={} )
          unless Hash === old_s and Hash === new_s
            logger.error 'Bad old or new sessions provided.'
            return cur
          end
              
          delete = old_s.keys - new_s.keys
          logger.info "//@#{sid}: delete #{delete*','}" if not delete.empty?
          delete.each{ |k| cur.delete(k) }

          update = new_s.keys.select do |k| 
            logger.debug "Update #{k}-#{new_s[k] != old_s[k]}? #{new_s[k].inspect} - #{old_s[k].inspect}";
            new_s[k] != old_s[k]
          end
          
          logger.info "//@#{sid}: update #{update*','}" if not update.empty?          
          update.each{ |k| cur[k] = new_s[k] }          
          cur
        end
        
        # Logger handle
        def logger
          @logger
        end
      
        # Set the log level                    
        def set_log_level( level )
          case level
            when :fatal
              Logger::FATAL
            when :error
              Logger::ERROR
            when :warn
              Logger::WARN
            when :info
              Logger::INFO
            when :debug
              Logger::DEBUG
            else
              Logger::INFO
            end
        end
        
    end
  end
end
