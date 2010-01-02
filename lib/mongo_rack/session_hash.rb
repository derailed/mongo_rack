# Snagged HashWithIndifferentAccess for A/S
module MongoRack
  class SessionHash < Hash
    
    # Need to enable users to access session using either a symbol or a string as key
    # This call wraps hash to provide this kind of access. No default allowed here. If a key
    # is not found nil will be returned.
    def initialize(constructor = {})
      if constructor.is_a?(Hash)
        super(constructor)
        update(constructor)        
        self.default = nil        
      else
        super(constructor)
      end
    end

    # Checks for default value. If key does not exits returns default for hash
    def default(key = nil)
      if key.is_a?(Symbol) && include?(key = key.to_s)
        self[key]
      else
        super
      end
    end

    alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
    alias_method :regular_update, :update unless method_defined?(:regular_update)

    # Assigns a new value to the hash:
    #
    #   hash = SessionHash.new
    #   hash[:key] = "value"
    #
    def []=(key, value)
      regular_writer(convert_key(key), convert_value(value))
    end

    # Updates the instantized hash with values from the second:
    # 
    #   hash_1 = SessionHash.new
    #   hash_1[:key] = "value"
    # 
    #   hash_2 = SessionHash.new
    #   hash_2[:key] = "New Value!"
    # 
    #   hash_1.update(hash_2) # => {"key"=>"New Value!"}
    # 
    def update(other_hash)
      other_hash.each_pair { |key, value| regular_writer(convert_key(key), convert_value(value)) }
      self
    end

    alias_method :merge!, :update

    # Checks the hash for a key matching the argument passed in:
    #
    #   hash = SessionHash.new
    #   hash["key"] = "value"
    #   hash.key? :key  # => true
    #   hash.key? "key" # => true
    #
    def key?(key)
      super(convert_key(key))
    end

    alias_method :include?, :key?
    alias_method :has_key?, :key?
    alias_method :member?, :key?

    # Fetches the value for the specified key, same as doing hash[key]
    def fetch(key, *extras)
      super(convert_key(key), *extras)
    end

    # Returns an array of the values at the specified indices:
    #
    #   hash = SessionHash.new
    #   hash[:a] = "x"
    #   hash[:b] = "y"
    #   hash.values_at("a", "b") # => ["x", "y"]
    #
    def values_at(*indices)
      indices.collect {|key| self[convert_key(key)]}
    end

    # Returns an exact copy of the hash.
    def dup
      SessionHash.new(self)
    end

    # Merges the instantized and the specified hashes together, giving precedence to the values from the second hash
    # Does not overwrite the existing hash.
    def merge(hash)
      self.dup.update(hash)
    end
    
    # Removes a specified key from the hash.
    def delete(key)
      super(convert_key(key))
    end

    #:nodoc:
    def stringify_keys!; self end
    #:nodoc:    
    def symbolize_keys!; self end
    #:nodoc:    
    def to_options!; self end

    # Convert to a Hash with String keys.
    def to_hash
      Hash.new(default).merge(self)
    end

    # =========================================================================
    private

      # converts key to string if symbol    
      def convert_key(key)
        key.kind_of?(Symbol) ? key.to_s : key
      end

      # check value and converts sub obj to session hash if any
      def convert_value(value)
        case value
          when Hash
            value.with_session_access
          when Array
            value.collect { |e| e.is_a?(Hash) ? e.with_session_access : e }
          else
            value
        end
      end
  end
end

module MongoRack
  module SessionAccess
    def with_session_access
      hash = MongoRack::SessionHash.new( self )
      hash
    end
  end
end