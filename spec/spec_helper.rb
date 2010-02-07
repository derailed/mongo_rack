require 'rubygems'
require 'rack'
require 'rack/test'
require 'rack/response'
require 'yaml'

require File.expand_path( File.join( File.dirname(__FILE__), %w[.. lib mongo_rack] ) )

Spec::Runner.configure do |config|
end

def mongo_check( res, key, val )
  session_id = res['Set-Cookie'].match( /^#{@session_key}=(.*?);.*?/ )[1]
  result     = @sessions.find_one( { :_id => session_id } )
  result.should_not be_nil
  ses       = YAML.load( result['data'] )
  ses[key.to_s].should == val    
end

def clear_sessions
  @sessions.remove()
end