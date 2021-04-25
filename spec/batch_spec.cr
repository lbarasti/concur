require "./spec_helper"

record T, v : Int32

describe Concur do
  describe "#batch where 6 items are published instantly and the rest are emitted every 4 seconds" do
    it "emits two 3-element bundles and a 1-element bundle in the second 1-second bucket" do
      batch_size = 3
      c = source(1..10)
        .map{ |v| sleep 4 if v > batch_size * 2 + 1; T.new(v) }
        .batch(batch_size, 1.seconds)
      t_0 = Time.utc
      c.receive.size.should eq batch_size
      c.receive.size.should eq batch_size
      assert_elapsed t_0, 0.0
      c.receive.size.should eq 1
      assert_elapsed t_0, 2.0
    end
  end

  describe "#batch where source emits no element in `interval` time" do
    it "sends an empty array after the given `interval` (1 second)" do
      c = source(1..10)
        .map{ |v| sleep 4; T.new(v) }
        .batch(2, 1.seconds)
      t_0 = Time.utc
      c.receive.should eq ([] of T)
      assert_elapsed t_0, 1.0
    end
  end
end