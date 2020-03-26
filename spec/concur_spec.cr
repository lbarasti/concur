require "./spec_helper"

class Msg; getter id; def initialize(@id : Int32); end; end
abstract class Event; end
class Processed < Event; getter v; def initialize(@v : Int32); end; end
ch = Channel(Msg).new
bus = Channel(Event).new
spawn do
  bus.listen {|v| puts v}
end

describe Concur do
  describe "#source" do
    it "emits each element of an enumerable" do
      ar = (1..3)
      s = source(ar)
      ar.map {|v| s.receive.should eq(v) }
      
    end
    it "closes the channel when the enumerable ends" do
      s = source("one two three".split)
      3.times { s.receive }
      expect_raises(Channel::ClosedError) {
        s.receive
      }
    end
    it "handles infinite collections" do
      ar = [1, 3, 5]
      cyc = ar.cycle
      s = source(cyc)
      10.times { |i| s.receive.should eq(ar[i%3]) }
    end
  end

  describe "#map" do
    it "applies a function to each value" do
      fact = source(1..3).map { |v|
        v * 2
      }
      fact.receive.should eq(2)
      fact.receive.should eq(4)
      fact.receive.should eq(6)
    end
    it "supports concurrent processing" do
      fact = source(1..3).map(workers: 2) { |v|
        sleep rand
        v * 2
      }
      expected = [2,4,6]
      actual = 3.times
        .map { fact.receive }
        .to_a
        .sort
      expected.should eq actual
      expect_raises(Channel::ClosedError) {
        fact.receive
      }
    end
  end

  describe "#map_with_state" do
    size = 10
    it "passes state through subsequent calls" do
      ch = source(1..size).map_with_state(0) { |state, v|
        {state + 1, v * v + state}
      }
      actual = size.times
        .map { ch.receive }
        .to_a
      expected = (1..size).map{|v| v * v + v - 1}
      actual.should eq expected
      expect_raises(Channel::ClosedError) {
        ch.receive
      }
    end
    it "can deal with arbitrarily complex state" do
      ch = source(1..size).map_with_state({previous: 0}) { |state, v|
        next_value = state[:previous] + v * v
        next_state = {previous: next_value}
        {next_state, next_value}
      }
      actual = size.times
        .map{ ch.receive }
        .to_a
      expected = (1..size).map { |v| (1..v).map(&.**(2)).sum }
      actual.should eq expected
    end
  end

  describe "#zip" do
    size = 10
    it "pairs values coming from different streams" do
      a = source(1..size)
      b = source(1..size).map(&.-)
      ch = a.zip(b) { |a_i, b_i|
        a_i + b_i
      }
      actual = size.times.map { ch.receive }.to_a
      (1..size).map{ 0 }.to_a.should eq actual
      expect_raises(Channel::ClosedError) {
        ch.receive
      }
    end
  end

  describe "#scan" do
    it "returns the accumulated values" do
      fact = source(1..4).scan(1) { |acc, v|
        acc * v
      }
      fact.receive.should eq(1)
      fact.receive.should eq(2)
      fact.receive.should eq(6)
      fact.receive.should eq(24)
    end
    it "closes the channel when the input stream closes" do
      s = source([1]).scan(0) { |acc, v| v + acc }
      s.receive
      expect_raises(Channel::ClosedError) {
        s.receive
      }
    end
  end

  describe "#broadcast" do
    it "emits elements from its input port to all of its output ports" do
      a, b, c = source(1..4).broadcast(3)
      (1..4).each { |v|
        a.receive.should eq(v)
        b.receive.should eq(v)
        c.receive.should eq(v)
      }
      [a,b,c].each { |ch|
        expect_raises(Channel::ClosedError) {
          ch.receive
        }
      }
    end
  end
end
