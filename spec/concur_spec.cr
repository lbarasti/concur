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

    it "supports generator functions" do
      size = 10
      initial_state = rand(128)
      s = source(initial_state) { |state|
        {state + 1, "#{state ** 2}"}
      }
      actual = size.times.map { s.receive }.to_a
      expected = (initial_state..initial_state + size - 1)
        .map(&.**(2).to_s)
        .to_a

      actual.should eq expected
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

  describe "#map" do
    size = 10
    it "passes state through subsequent calls" do
      ch = source(1..size).map(0) { |state, v|
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
      ch = source(1..size).map({previous: 0}) { |state, v|
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

  describe "#merge" do
    size = 10
    it "pipes values coming from different streams into a single one" do
      a = source(1..size)
      b = source(1..size).map(&.-)
      ch = a.merge(b).scan(0) { |sum, b| sum + b }
      (size * 2 - 1).times { ch.receive }
      ch.receive.should eq 0
    end

    it "will continue receiving values after one of the upstream channels has closed" do
      a = source(1..size * 2)
      b = source(1..size)
      ch = a.merge(b)
      (size * 3).times { ch.receive }
    end

    it "will close the downstream channel once both sources have been exhausted" do
      a = source(1..size)
      b = source(1..size)
      ch = a.merge(b)
      (size * 2).times { ch.receive }
      expect_raises(Channel::ClosedError) {
        ch.receive
      }
    end
  end

  describe "#select" do
    size = 10
    it "filters values based on a predicate" do
      expected = [1.0, 3.0, 5.0, 7.0, 9.0]

      take(source(1..size).select(&.odd?), 5)
        .should eq expected
    end
  end

  describe "#reject" do
    size = 10
    it "rejects values based on a predicate" do
      expected = [2.0, 4.0, 6.0, 8.0]

      take(source(1...size).reject(&.odd?), 4)
        .should eq expected
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

  describe "#rate_limit" do
    it "emits elements with the given rate" do
      max_burst = 2
      a = source(1..4)
        .rate_limit(items_per_sec: 1, max_burst: max_burst)
      start_time = Time.utc
      
      max_burst.times { a.receive }
      assert_elapsed start_time, 0.0
      a.receive
      assert_elapsed start_time, 1.0
      a.receive
      assert_elapsed start_time, 2.0
    end
  end
end
