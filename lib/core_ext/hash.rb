require File.join( File.dirname(__FILE__), %w[.. mongo_rack session_hash] )

# Reopen hash to add session access ie indifferent access to keys as symb or str
class Hash
  include MongoRack::SessionAccess
end