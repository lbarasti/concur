module Concur
  macro debug(msg, enable)
    {% if enable %} puts "#{Fiber.current.name} > #{{{msg}}}" {% end %}
  end
  module InChannel(T)
    abstract def receive
    abstract def receive?
  end
  module OutChannel(T)
    abstract def send(value : T)
  end

  def timer(t : Time::Span, name = nil, debug? = false) : Channel(Nil)
    Channel(Nil).new.tap { |timeout|
      spawn(name: name) do
        debug("spawned", debug?)
        sleep t
        timeout.close()
      end
    }
  end


  def source(input : Enumerable(T)) : Channel(T) forall T
    Channel(T).new.tap { |stream|
      spawn do
        input.each { |value|
          stream.send value
        }
        stream.close()
      end
    }
  end

  def every(t : Time::Span, name = nil, terminate = InChannel(Time).new, debug? = false, &block : -> T) : InChannel(T) forall T
    Channel(T).new.tap { |values|
      spawn(name: name) do
        debug("spawned", debug?)
        (1..).each do |i|
          debug("loop #{(start = Time.utc) && i}", debug?)

          select
          when values.send block.call
            debug("loop #{i} (#{(Time.utc - start).total_milliseconds}ms)", debug?)
          when time = terminate.receive
            debug("Interrupted at #{time}", debug?)
            break
          end
        rescue Channel::ClosedError
          debug("close signal received", debug?)
          break
        end
      ensure
        debug("Shutting down", debug?)
        values.close()
      end
    }
  end

  def process(in_stream : InChannel(T), name = nil,
              workers = 1, debug? = false, &block : T -> K) : InChannel(K) forall T, Q, K
    Channel(K).new.tap { |pipe|
      workers.times { |w_i|
        spawn(name: "#{name}_#{w_i}") do
          debug("spawned", debug?)
          (1..).each do |i|
            debug("loop #{(start = Time.utc) && i}", debug?)
            
            received = in_stream.receive

            debug("received #{received}", debug?)

            pipe.send block.call(received)
            
            debug("loop #{i} (#{(Time.utc - start).total_milliseconds}ms)", debug?)
          rescue Channel::ClosedError
            debug("received closing signal", debug?)
            break
          end
        ensure
          debug("Shutting down", debug?)
          pipe.close() if w_i == 0
        end
      }
    }
  end
end

abstract class ::Channel(T) 
  include Concur::InChannel(T)
  include Concur::OutChannel(T)

  def map(workers = 1, &block : T -> V) : Channel(V) forall T,V
    Channel(V).new.tap { |stream|
      countdown = Channel(Nil).new(workers)
      workers.times { |w_i|
        spawn(name: "#{Fiber.current.name} > #{w_i}") do
          self.listen { |v|
            stream.send block.call(v)
          }
        ensure
          countdown.send(nil)
        end
      }
      spawn(name: "#{Fiber.current.name} > countdown") do
        workers.times { countdown.receive }
        countdown.close
        stream.close
      end
    }
  end

  def scan(acc : U, &block : U,T -> V) : Channel(V) forall U,V
    Channel(V).new.tap { |stream|
      spawn do
        self.listen { |v|
          acc = block.call(acc, v)
          stream.send acc
        }
        stream.close()
      end
    }
  end

  # TODO define a macro to return a Tuple
  def broadcast(out_ports = 2, name = nil)
    out_ports.times.map { Channel(T).new }.to_a.tap { |streams|
      spawn(name: name) do
        self.listen { |v|
          streams.each(&.send(v))
        }
        streams.each(&.close())
      end
    }
  end

  def listen(&block : T ->)
    loop do
      block.call(self.receive)
    rescue Channel::ClosedError
      puts "#{Fiber.current.name} rescuing"
      break
    end
  end
end
