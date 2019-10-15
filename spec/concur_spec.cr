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
  it "processes on multiple concurrent fibers" do
    k = 100
    out_stream = process(ch, name = "processor", workers = 2, debug = true) { |value|
      bus.send Processed.new(value.id)
      value.id + 2
    }
    spawn do
      k.times do ch.send Msg.new(1) end
    end
    k.times do
      out_stream.receive
    end
    ch.close()
  end
end
