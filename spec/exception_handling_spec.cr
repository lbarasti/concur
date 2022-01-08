require "./spec_helper"

describe Concur do
  size = 10
  describe "#map exception handling" do
    it "will swallow any exceptions if no error callback is given" do
      computed = source(1..size)
        .map { |v|
          if v % 2 == 0
            v
          else
            raise Exception.new(v.to_s)
          end
        }.take(size)
      computed.should eq (1..size).select(&.even?)
    end

    it "will invoke the given error callback if an exception is raised" do
      err_ch = Channel(Exception).new(size)
      on_err = -> (x : Int32, ex : Exception) {
        err_ch.send ex
      }

      computed = source(1..size)
        .map(on_error: on_err) { |v|
          if v % 2 == 0
            v
          else
            raise Exception.new(v.to_s)
          end
        }.take(size)

      computed.should eq (1..size).select(&.even?)

      err_ch.take(5)
        .map { |ex| ex.message.not_nil!.to_i }
        .should eq (1..size).select(&.odd?)
    end
  end

  describe "#select exception handling" do
    it "will swallow any exceptions if no error callback is given" do
      source(1..size).select { |v|
        v < 6 ? true : raise Exception.new
      }.take(size).should eq (1..5).to_a
    end

    it "will invoke the given error callback if an exception is raised" do
      error_count = 0
      on_err = ->(t : Int32, ex : Exception) {
        error_count += 1
      }
      source(1..size).select(on_error: on_err) { |v|
        v < 6 ? true : raise Exception.new
      }.take(size).should eq (1..5).to_a

      error_count.should eq 5
    end
  end

  describe "#partition exception handling" do
    it "will swallow any exceptions if no error callback is given" do
      pass, fail = source(1..size).partition { |v|
        v < 6 ? true : raise Exception.new
      }
      pass.take(size).should eq (1..5).to_a
      fail.take(size).should be_empty
    end

    it "will invoke the given error callback if an exception is raised" do
      error_count = 0
      on_err = ->(t : Int32, ex : Exception) {
        error_count += 1
      }
      pass, fail = source(1..size).partition(on_error: on_err) { |v|
        v < 6 ? true : raise Exception.new
      }
      pass.take(size).should eq (1..5).to_a
      fail.take(size).should be_empty

      error_count.should eq 5
    end
  end

  describe "#zip exception handling" do
    it "will swallow any exceptions if no error callback is given" do
      source(1..size)
        .zip(source(2..size + 1)) { |a, b|
          if a + b < 10
            a + b
          else
            raise Exception.new((a + b).to_s)
          end
        }.take(size).should eq [3, 5, 7, 9]
    end

    it "will invoke the given error callback if an exception is raised" do
      error_count = 0
      on_err = ->(tu : {Int32, Int32}, ex : Exception) {
        error_count += 1
      }
      source(1..size)
        .zip(source(2..size + 1), on_error: on_err) { |a, b|
          if a + b < 10
            a + b
          else
            raise Exception.new((a + b).to_s)
          end
        }.take(size).should eq [3, 5, 7, 9]
      error_count.should eq 6
    end
  end
end