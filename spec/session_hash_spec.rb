require File.expand_path(File.join(File.dirname(__FILE__), %w[spec_helper]))

describe MongoRack::SessionHash do
  before :all do
    @sessions = MongoRack::SessionHash.new( :fred => 10, :blee => "duh", 'crap' => 20 )
  end
  
  it "should pass non hash arg to hash class correctly" do
    hash = MongoRack::SessionHash.new( "BumbleBeeTuna" )
    hash[:c].should == "BumbleBeeTuna"
  end
  
  describe "indiscrement access" do
    it "should find a symbol keys correctly" do
      @sessions[:fred].should == 10
      @sessions[:blee].should == "duh"
    end
    
    it "should find a string key correctly" do
      @sessions['fred'].should == 10
      @sessions[:crap].should  == 20
      @sessions.fetch(:crap).should == @sessions.fetch('crap')
    end
    
    it "should return nil if a key is not in the hash" do  
      @sessions[:zob].should be_nil
    end
    
    it "should find values at indices correctly" do
      @sessions.values_at( :fred, :blee ).should   == [10, 'duh']
      @sessions.values_at( 'fred', 'blee' ).should == [10, 'duh']
      @sessions.values_at( :fred, 'blee' ).should  == [10, 'duh']      
    end
    
    it "should convert sub hashes correctly" do
      @sessions[:blee] = { "bobo" => 10, :ema => "Hello" }
      @sessions[:blee][:bobo].should == 10
      @sessions[:blee]['ema'].should == "Hello"
    end
  end  
end
