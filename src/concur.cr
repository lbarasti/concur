module Concur
  def source(input : Enumerable(T), name = nil) : Channel(T) forall T
    Channel(T).new.tap { |stream|
      spawn(name: name) do
        input.each { |value|
          stream.send value
        }
        stream.close()
      end
    }
  end

  def every(t : Time::Span, name = nil, terminate = Channel(Time).new, debug? = false, &block : -> T) : Channel(T) forall T
    Channel(T).new.tap { |values|
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
        in_stream.listen { |enumerable|
          enumerable.each { |v|
            out_stream.send(v)
          }
        }
      end
    }
  end

  def merge(stream_1 : Channel(K), stream_2 : Channel(J), name = nil) : Channel(K | J) forall K,J
    Channel(K | J).new.tap { |out_stream|
      spawn do
        loop do          
          out_stream.send Channel.receive_first(stream_1, stream_2)
        rescue Channel::ClosedError
          puts "#{Fiber.current.name} rescuing"
          break
        end
      end
    }
  end
end

abstract class ::Channel(T) 

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

  def scan(acc : U, &block : U,T -> U) : Channel(U) forall U
    Channel(U).new.tap { |stream|
      spawn do
        self.listen { |v|
          acc = block.call(acc, v)
          stream.send acc
        }
        stream.close()
      end
    }
  end

  # def zip(channel : Channel(U), name = nil) : Channel({T,U}) forall U
  #   Channel({T,U}).new.tap { |stream|
  #     spawn do
  #       self.listen
  #     end
  #   }
  # end

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

  def partition(&predicate : T -> Bool) : {Channel(T), Channel(T)}
    {Channel(T).new, Channel(T).new}.tap { |pass, fail|
      spawn do
        self.listen { |v|
          predicate.call(v) ? (pass.send(v)) : (fail.send(v))
        }
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
