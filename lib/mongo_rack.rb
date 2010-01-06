require 'rack/session/abstract/id'
require 'mongo'
require File.expand_path( File.join( File.dirname(__FILE__), %w[mongo_rack session_hash.rb] ) )
require File.expand_path( File.join( File.dirname(__FILE__), %w[core_ext hash.rb] ) )

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
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge \
        :server       => 'localhost:27017/mongo_session/sessions',
        :pool_size    => 1,
        :pool_timeout => 1.0

      # Initializes mongo_rack. Pass in options for default override.
      def initialize(app, options={})
        super

        host, port, db_name, cltn_name = parse_server_desc( @default_options[:server] )
        
        @mutex      = Mutex.new      
        @connection = ::Mongo::Connection.new( host, port,
          :pool_size => @default_options[:pool_size],
          :timeout   => @default_options[:pool_timeout] )
        @db         = @connection.db( db_name )
        @sessions   = @db[cltn_name]
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

        # fetch session with optional session id
        def _get_session(env, sid)
          if sid
            ses_obj = sessions.find_one( { :_id => sid } )
            session = MongoRack::SessionHash.new( ses_obj['data'] ) if ses_obj and fresh?( ses_obj )
          end
    
          unless sid and session
            env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
            session = {}
            sid     = generate_sid
            ret     = sessions.save( { :_id => sid, :data => session } )
            raise "Session collision on '#{sid.inspect}'" unless ret
          end
          session.instance_variable_set( '@old', MongoRack::SessionHash.new.merge(session) )
          return [sid, session]        
        rescue => boom
          warn "#{self} is unable to find server."
          warn $!.inspect
          return [ nil, {} ]
        end
            
        # update session information with new settings
        def _set_session(env, sid, new_session, options)
          ses_obj = sessions.find_one( { :_id => sid } )
          if ses_obj
            session = MongoRack::SessionHash.new( ses_obj['data'] )
          else
            session = MongoRack::SessionHash.new
          end
    
          if options[:renew] or options[:drop]
            sessions.remove( { :_id => sid } )
            return false if options[:drop]
            sid = generate_sid
            sessions.insert( {:_id => sid, :data => {} } )
          end
          old_session = new_session.instance_variable_get('@old') || MongoRack::SessionHash.new
          merged = merge_sessions( sid, old_session, new_session, session )

          expiry = options[:expire_after]
          expiry = expiry ? Time.now + options[:expire_after] : 0

          # BOZO ! Use upserts here if minor changes ?
          sessions.save( { :_id => sid, :data => merged, :expire => expiry } )
          return sid
        rescue => boom
          warn "#{self} is unable to find server."
          warn $!.inspect
          return false
        end

        # merge old, new to current session state
        def merge_sessions( sid, old_s, new_s, cur={} )
          unless Hash === old_s and Hash === new_s
            warn 'Bad old or new sessions provided.'
            return cur
          end
                    
          delete = old_s.keys - new_s.keys
          warn "//@#{sid}: delete #{delete*','}" if $VERBOSE and not delete.empty?
          delete.each{ |k| cur.delete(k) }

          update = new_s.keys.select{ |k| new_s[k] != old_s[k] }
          warn "//@#{sid}: update #{update*','}" if $VERBOSE and not update.empty?          
          update.each{ |k| cur[k] = new_s[k] }
          
          cur
        end
    end
  end
end
