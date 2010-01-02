require File.join(File.dirname(__FILE__), %w[spec_helper])

describe MongoRack::SessionHash do
  before :all do
    @sessions = MongoRack::SessionHash.new( :fred => 10, :blee => "duh" )
  end
  
  it "should find a key correctly" do
    @sessions[:fred].should == 10
    @sessions[:blee].should == "duh"
  end
  
  it "should return nil if a key is not in the hash" do
    @sessions[:zob].should be_nil
  end
end
