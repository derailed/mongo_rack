require File.expand_path(File.join(File.dirname(__FILE__), %w[spec_helper]))
require 'core_ext/hash'

describe Rack::Session::Mongo do
  before :all do
    @session_key   = 'rack.session'
    @session_match = /#{@session_key}=[0-9a-fA-F]+;/    
    @db_name       = 'mongo_rack_test'
    @cltn_name     = 'sessions'
    
    @con      = Mongo::Connection.new
    @db       = @con.db( @db_name )
    @sessions = @db['sessions']
    
    @incrementor = lambda do |env|
      env[@session_key]['counter'] ||= 0
      env[@session_key]['counter']  += 1
      Rack::Response.new( env[@session_key].inspect ).to_a
    end    
  end

  it "should connect to a valid server" do
    Rack::Session::Mongo.new( @incrementor, :server => "localhost:27017/#{@db_name}/#{@cltn_name}" )
  end
  
  it "should fail if bad server specified" do
    lambda do
      Rack::Session::Mongo.new( @incrementor, :server => "blee:1111/#{@db_name}/#{@cltn_name}" )
    end.should raise_error( Mongo::ConnectionFailure )
  end

  describe "cookies" do    
    before :each do 
      @pool = Rack::Session::Mongo.new( @incrementor, :server => "localhost:27017/#{@db_name}/#{@cltn_name}" ) 
    end
    
    it "should create a new cookie correctly" do
      res = Rack::MockRequest.new( @pool ).get( "/", 'rack.multithread' => false )
      res['Set-Cookie'].should match( /^#{@session_key}=/ )
      res.body.should == '{"counter"=>1}'
      session_id = res['Set-Cookie'].match( /^#{@session_key}=(.*?);.*?/ )[1]
      mongo_check( res, :counter, 1 )
    end  
  
    it "should determine a session from a cookie" do
      req    = Rack::MockRequest.new( @pool )
      res    = req.get("/", 'rack.multithread' => false )
      cookie = res["Set-Cookie"]
      req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false ).body.should == '{"counter"=>2}'
      mongo_check( res, :counter, 2 )
      req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false ).body.should == '{"counter"=>3}'
      mongo_check( res, :counter, 3 )    
    end
    
    it "survives nonexistant cookies" do
      bad_cookie = "rack.session=bumblebeetuna"
      res = Rack::MockRequest.new( @pool ).get("/", "HTTP_COOKIE" => bad_cookie, 'rack.multithread' => false )
      res.body.should == '{"counter"=>1}'
      cookie = res["Set-Cookie"][@session_match]
      cookie.should_not match( /#{bad_cookie}/ )
    end
    
    it "maintains freshness" do
      pool = Rack::Session::Mongo.new( @incrementor, :server => "localhost:27017/#{@db_name}/#{@cltn_name}", :expire_after => 1 )
      res = Rack::MockRequest.new(pool).get('/', 'rack.multithread' => false )
      res.body.should include('"counter"=>1')
      cookie = res["Set-Cookie"]
      res = Rack::MockRequest.new(pool).get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res["Set-Cookie"].should == cookie
      res.body.should include('"counter"=>2')
      puts 'Sleeping to expire session' if $DEBUG
      sleep 2
      res = Rack::MockRequest.new(pool).get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res["Set-Cookie"].should_not == cookie
      res.body.should include( '"counter"=>1' )
    end    
    
    it "deletes cookies with :drop option" do
      drop_session = lambda do |env|
        env['rack.session.options'][:drop] = true
        @incrementor.call(env)
      end
            
      req  = Rack::MockRequest.new(@pool)
      drop = Rack::Utils::Context.new(@pool, drop_session)
      dreq = Rack::MockRequest.new(drop)

      res0 = req.get("/", 'rack.multithread' => false )
      session = (cookie = res0["Set-Cookie"])[@session_match]
      res0.body.should == '{"counter"=>1}'

      res1 = req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res1["Set-Cookie"][@session_match].should == session
      res1.body.should == '{"counter"=>2}'

      res2 = dreq.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res2["Set-Cookie"].should == nil
      res2.body.should == '{"counter"=>3}'

      res3 = req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false)
      res3["Set-Cookie"][@session_match].should_not == session
      res3.body.should == '{"counter"=>1}'
    end
    
    it "provides new session id with :renew option" do
      renew_session = lambda do |env|
        env['rack.session.options'][:renew] = true
        @incrementor.call(env)
      end
      
      req = Rack::MockRequest.new(@pool)
      renew = Rack::Utils::Context.new(@pool, renew_session)
      rreq = Rack::MockRequest.new(renew)

      res0 = req.get("/", 'rack.multithread' => false )
      session = (cookie = res0["Set-Cookie"])[@session_match]
      res0.body.should == '{"counter"=>1}'

      res1 = req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res1["Set-Cookie"][@session_match].should == session
      res1.body.should == '{"counter"=>2}'

      res2 = rreq.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      new_cookie = res2["Set-Cookie"]
      new_session = new_cookie[@session_match]
      new_session.should_not == session
      res2.body.should == '{"counter"=>3}'

      res3 = req.get("/", "HTTP_COOKIE" => new_cookie, 'rack.multithread' => false )
      res3["Set-Cookie"][@session_match].should == new_session
      res3.body.should == '{"counter"=>4}'
    end
    
    it "omits cookie with :defer option" do
      defer_session = lambda do |env|
        env['rack.session.options'][:defer] = true
        @incrementor.call(env)
      end
      
      req   = Rack::MockRequest.new(@pool)
      defer = Rack::Utils::Context.new(@pool, defer_session)
      dreq  = Rack::MockRequest.new(defer)

      res0 = req.get("/", 'rack.multithread' => false )
      session = (cookie = res0["Set-Cookie"])[@session_match]
      res0.body.should == '{"counter"=>1}'

      res1 = req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res1["Set-Cookie"][@session_match].should == session
      res1.body.should == '{"counter"=>2}'

      res2 = dreq.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res2["Set-Cookie"].should == nil
      res2.body.should == '{"counter"=>3}'

      res3 = req.get("/", "HTTP_COOKIE" => cookie, 'rack.multithread' => false )
      res3["Set-Cookie"][@session_match].should == session
      res3.body.should == '{"counter"=>4}'
    end
    
    # BOZO !! Review...
    it "multithread: should cleanly merge sessions" do
      pending do
        @pool = Rack::Session::Mongo.new( @incrementor, :server => "localhost:27017/#{@db_name}/#{@cltn_name}", :pool_size => 10 ) 

        req = Rack::MockRequest.new( @pool )

        res             = req.get('/')
        res.body.should == '{"counter"=>1}'
        cookie          = res["Set-Cookie"]
        sess_id         = cookie[/#{@pool.key}=([^,;]+)/,1]

        r = Array.new( 10 ) do 
          Thread.new( req ) do |run|
            req.get( "/", "HTTP_COOKIE" => cookie, 'rack.multithread' => true )
          end
        end.reverse.map{ |t| t.join.value }
        
        r.each do |res|
          res['Set-Cookie'].should == cookie
          res.body.should include( '"counter"=>2' )
        end
      
        drop_counter = proc do |env|
          env['rack.session'].delete 'counter'
          env['rack.session']['foo'] = 'bar'
          [200, {'Content-Type'=>'text/plain'}, env['rack.session'].inspect]
        end
        tses = Rack::Utils::Context.new @pool, drop_counter
        treq = Rack::MockRequest.new( tses )
      
        tnum = 10
        r = Array.new(tnum) do
          Thread.new(treq) do |run|
            run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
          end
        end.reverse.map{|t| t.join.value }
        r.each do |res|
          res['Set-Cookie'].should == cookie
          res.body.should include('"foo"=>"bar"')
        end
      
        result = @pool.sessions.find_one( {:_id => sess_id } )
        result.should_not be_nil
        session = YAML.load( result['data'] )
        session.size.should == 1
        session['counter'].should be_nil
        session['foo'].should == 'bar'      
      end
    end
  end

  describe "serialization" do
    before( :all ) do
      @pool = Rack::Session::Mongo.new( @incrementor, :server => "localhost:27017/#{@db_name}/#{@cltn_name}" )
      @env  = {}
      @opts = {}
    end
    
    it "should store a hash in session correctly" do
      sid = 10
      ses = { 'a' => 1, 'b' => 2 }
      @pool.send(:_set_session, @env, sid, ses, @opts )
      results = @pool.send(:_get_session, @env, sid )
      results.last.should == ses
    end
    
    it "should store an object in session correctly" do
      sid = 11
      fred = Fred.new( 10, "Hello" )
      ses = { :fred => fred }
      @pool.send(:_set_session, @env, sid, ses, @opts )
      results = @pool.send(:_get_session, @env, sid )
      [:fred, 'fred'].each do |key|
        results.last[key].blee.should  == 10
        results.last[key].duh.should   == "Hello"
        results.last[key].zob.should   == 100
      end
    end
  end
  
  class Fred
    attr_accessor :blee, :duh, :zob
    def initialize( blee, duh )
      @blee = blee
      @duh  = duh
      @zob  = 100
    end
  end
  
end
