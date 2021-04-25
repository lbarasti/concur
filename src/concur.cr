require "rate_limiter"

module Concur
  def source(input : Enumerable(T), name = nil, buffer_size = 0) : Channel(T) forall T
    Channel(T).new(buffer_size).tap { |stream|
      spawn(name: name) do
        input.each { |value|
          stream.send value
        }
        stream.close()
      end
    }
  end
  
  def source(initial_state : S, name = nil, buffer_size = 0, &block : S -> {S, V}) forall S, V
    Channel(V).new(buffer_size).tap { |stream|
      spawn(name: name) do
        state = initial_state
        loop do
          state, value = block.call(state)
          stream.send value
        end
      end
    }
  end

  def every(t : Time::Span, name = nil, buffer_size = 0, terminate = Channel(Time).new, &block : -> T) : Channel(T) forall T
    Channel(T).new(buffer_size).tap { |values|
      spawn(name: name) do
        loop do
          select
          when timeout(t)
            values.send block.call
          when time = terminate.receive
            break
          end
        rescue Channel::ClosedError
          break
        end
      ensure
        values.close()
      end
    }
  end

  def flatten(in_stream : Channel(Enumerable(K)), name = nil) : Channel(K) forall K
    Channel(K).new.tap { |out_stream|
      spawn do
        loop do
          in_stream.receive.each { |v|
            out_stream.send(v)
          }
        end
      rescue Channel::ClosedError
        out_stream.close
      end
    }
  end
end

abstract class ::Channel(T)

  # Pipes values from two channels into a single one.
  # Note. If both channels have values ready to be received, then one will be selected at random. 
  def merge(channel : Channel(J), name = nil) : Channel(T | J) forall J
    channels = [self, channel]
    Channel(T | J).new.tap { |out_stream|
      spawn do
        loop do          
          out_stream.send Channel.receive_first(channels.shuffle) # shuffle to increase fairness
        rescue Channel::ClosedError
          channels.reject!(&.closed?)
          break if channels.empty?
        end
        out_stream.close
      end
    }
  end

  def rate_limit(items_per_sec : Float64, max_burst : Int32)
    rl = RateLimiter.new(rate: items_per_sec, max_burst: max_burst)

    Channel(T).new.tap { |stream|
      spawn do
        loop do
          rl.get
          stream.send self.receive
        end
      rescue Channel::ClosedError
        stream.close
      end
    }
  end
  
  def map(workers = 1, buffer_size = 0, name = nil, &block : T -> V) : Channel(V) forall V
    Channel(V).new(buffer_size).tap { |stream|
      countdown = Channel(Nil).new(workers)
      workers.times { |w_i|
        spawn(name: name || "#{Fiber.current.name} > #{w_i}") do
          self.listen { |v|
            stream.send block.call(v)
          }
        ensure
          countdown.send(nil)
        end
      }
      spawn(name: name || "#{Fiber.current.name} > countdown") do
        workers.times { countdown.receive }
        countdown.close
        stream.close
      end
    }
  end

  def map(initial_state : S, buffer_size = 0, name = nil, &block : S, T -> V) forall S,V
    state = initial_state
    self.map(name: name, buffer_size: buffer_size) { |t|
      state, v = block.call(state, t)
      v
    }
  end

  def scan(acc : U, buffer_size = 0, name = nil, &block : U,T -> U) : Channel(U) forall U
    Channel(U).new(buffer_size).tap { |stream|
      spawn(name: name) do
        self.listen { |v|
          acc = block.call(acc, v)
          stream.send acc
        }
        stream.close()
      end
    }
  end

  def zip(channel : Channel(U), name = nil, buffer_size = 0, &block : T,U -> V) : Channel(V) forall U,V
    Channel(V).new(buffer_size).tap { |stream|
      spawn(name: name) do
        loop do
          p1 = self.receive
          p2 = channel.receive

          stream.send block.call(p1,p2)
        end
      rescue Channel::ClosedError
        puts "#{Fiber.current.name} rescuing"
        stream.close
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

  def select(name = nil, &predicate : T -> Bool) : Channel(T)
    Channel(T).new.tap { |selected|
      spawn(name: name) do
        loop do
          v = self.receive
          predicate.call(v) ? selected.send(v) : nil
        end
      rescue Channel::ClosedError
        selected.close
      end
    }
  end

  def reject(name = nil, &predicate : T -> Bool) : Channel(T)
    self.select(name: name) { |v|
      !predicate.call(v)
    }
  end

  def partition(&predicate : T -> Bool) : {Channel(T), Channel(T)}
    {Channel(T).new, Channel(T).new}.tap { |pass, fail|
      spawn do
        self.listen { |v|
          predicate.call(v) ? (pass.send(v)) : (fail.send(v))
        }
      end
    }
  end

  # Sends batches of messages either every `size` messages received or every `interval`,
  # if a batch has not been sent within the last `interval`.
  def batch(size : Int32, interval : Time::Span, name = nil) : Channel(Enumerable(T))
    # TODO: assert on `size` and `interval`
    Channel(Enumerable(T)).new.tap { |out_stream|
      memory = Array(T).new(size)
      tick = every(interval) { nil }
      sent = false
      spawn(name: name) do
        loop do
          select
          when v = self.receive
            memory << v
            if memory.size >= size
              out_stream.send(memory.dup)
              memory.clear
              sent = true
            end
          when tick.receive
            unless sent
              out_stream.send(memory.dup)
              memory.clear
            end
            sent = false
          end
        end
      rescue Channel::ClosedError
        out_stream.send(memory.dup)
        out_stream.close
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

  def each(name = nil, &block : T -> )
    spawn(name: name) do
      loop do
        block.call(self.receive)
      rescue Channel::ClosedError
        break
      end
    end
  end
end
