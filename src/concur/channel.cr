require "./concur"

abstract class ::Channel(T)

  # Returns an enumerable of values received from `self` containing at most *max_items* elements.
  #
  # If `self` is closed in the process, then the returned enumerable might include fewer elements.
  def take(max_items : Int32)
    ([] of T).tap { |items|
      (1..max_items).each do
        items << self.receive
      rescue Channel::ClosedError
        break
      end
    }
  end

  # Returns a channel that receives values from both *self* and *other*, as soon as they are available.
  #
  # The returned channel is closed as soon as both the input channels are closed and empty - but will
  # continue to operate while at least one of them is open.
  #
  # NOTE: If both channels have values ready to be received, then one will be selected at random. 
  def merge(other : Channel(J), name = nil, buffer_size = 0) : Channel(T | J) forall J
    channels = [self, other]
    Channel(T | J).new(buffer_size).tap { |stream|
      spawn(name: name) do
        loop do
          stream.send Channel.receive_first(channels.shuffle) # shuffle to increase fairness
        rescue Channel::ClosedError
          channels.reject!(&.closed?)
          break if channels.empty?
        end
        stream.close
      end
    }
  end

  # Returns a channel that receives at most *items_per_sec* items per second from the
  # caller - or *max_burst* items, if no elements were received in a while.
  #
  # The returned channel is closed once `self` is closed and empty and a new value
  # can be received, based on the rate limiting parameters.
  #
  # Refer to the documentation of [RateLimiter](https://github.com/lbarasti/rate_limiter)
  # for more details.
  def rate_limit(items_per_sec : Float64, max_burst : Int32 = 1, name = nil, buffer_size = 0)
    rl = RateLimiter.new(rate: items_per_sec, max_burst: max_burst)

    Channel(T).new(buffer_size).tap { |stream|
      spawn(name: name) do
        loop do
          rl.get
          stream.send self.receive
        end
      rescue Channel::ClosedError
        stream.close
      end
    }
  end

  # Returns a channel that receives values from `self` transformed via *block*.
  #
  # A *workers* parameter can be supplied to make the computation of the block concurrent.
  # Note that, for *workers* > 1, no order guarantees are made.
  #
  # The returned channel will close once `self` is closed and empty, and all
  # the outstanding runs of *block* are completed.
  #
  # Any exception raised while evaluating *block* will be passed
  # to the optional callback *on_error*, together with the value that
  # triggered the error.
  #
  # Example:
  # ```
  # source([1,2,3])
  #   .map(workers: 2) { |v| sleep rand; v**2 } # => [4, 1, 9]
  # ```
  def map(
    workers = 1,
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &block : T -> V
  ) : Channel(V) forall V
    Channel(V).new(buffer_size).tap { |stream|
      countdown = Channel(Nil).new(workers)
      workers.times { |w_i|
        spawn(name: name.try { |s| "#{s}.#{w_i}" }) do
          self.listen { |t|
            begin
              res = block.call(t)
              stream.send res
            rescue ex
              on_error.call(t, ex)
            end
          }
        ensure
          countdown.send(nil)
        end
      }
      spawn(name: name.try { |s| "#{s}.countdown" }) do
        workers.times { countdown.receive }
        countdown.close
        stream.close
      end
    }
  end

  # Returns a channel that receives each value of the enumerables produced
  # applying *block* to values received by `self`.
  #
  # A *workers* parameter can be supplied to make the computation of the block concurrent.
  # Note that, for *workers* > 1, no order guarantees are made - see `#map` for an example.
  #
  # The returned channel is closed once `self` is closed and empty, and all
  # the outstanding runs of *block* are completed.
  #
  # See `#map` for details on the exception handling strategy.
  def flat_map(
    workers = 1,
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &block : T -> Enumerable(V)
  ) : Channel(V) forall V
    enum_stream = map(workers: workers, name: name.try{ |s| "#{s}.map" },
      on_error: on_error, &block)
    Concur.flatten(enum_stream, name, buffer_size)
  end

  # Returns a channel that receives values from `self` transformed via *block* and based
  # on the provided *initial_state*.
  #
  # NOTE: *block* is a function that takes the current state and a value received
  # from `self` and returns a tuple composed of the next state to be passed to the block
  # and the next value to be received by the returned channel.
  #
  # The returned channel is closed once `self` is closed and empty, and any outstanding
  # run of *block* is completed.
  #
  # See `#map` for details on the exception handling strategy.
  def map(
    initial_state : S,
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &block : S, T -> {S, V}
  ) forall S,V
    state = initial_state
    self.map(name: name, buffer_size: buffer_size, on_error: on_error) { |t|
      state, v = block.call(state, t)
      v
    }
  end

  # Returns a channel that receives each successive accumulated state produced by *block*,
  # based on the initial state *acc* and on the values received by `self`.
  #
  # The returned channel is closed once `self` is closed and empty, and any outstanding
  # run of *block* is completed.
  #
  # See `#map` for details on the exception handling strategy.
  def scan(
    acc : U,
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &block : U, T -> U
  ) : Channel(U) forall U
    map(acc, name, buffer_size, on_error) { |state, v|
      res = block.call(state, v)
      {res, res}
    }
  end

  # Returns a channel that receives tuples of values coming from `self` and *other*
  # transformed via *block*.
  #
  # The returned channel is closed once either `self` or `other` are closed and empty,
  # and any outstanding run of *block* is completed.
  #
  # See `#map` for details on the exception handling strategy.
  def zip(
    other : Channel(U),
    name = nil,
    buffer_size = 0,
    on_error = ->(tu : {T, U}, ex : Exception) {},
    &block : T, U -> V
  ) : Channel(V) forall U, V
    Channel(V).new(buffer_size).tap { |stream|
      spawn(name: name) do
        loop do
          p1 = self.receive
          p2 = other.receive

          begin
            res = block.call(p1, p2)
            stream.send res
          rescue ex
            on_error.call({p1, p2}, ex)
          end
        end
      rescue Channel::ClosedError
        stream.close
      end
    }
  end

  # Returns an array of *out_ports* channels which receive each value
  # received by `self`.
  #
  # The returned channels will close once `self` is closed and empty.
  #
  # If one of the returned channels is closed, then `#broadcast` will
  # close every other channel.
  #
  # NOTE: The rate at which values are received by each channel is limited
  # by the slowest consumer. Values are sent to channels in the order they
  # were returned.
  def broadcast(out_ports = 2, name = nil, buffer_size = 0) : Array(Channel(T))
    out_ports.times
      .map { Channel(T).new(buffer_size) }
      .to_a
      .tap { |streams|
        spawn(name: name) do
          self.listen { |v|
            streams.each(&.send(v))
          }
          streams.each(&.close)
        end
      }
  end

  # Returns a channel which receives values received by `self`
  # that satisfy the given *predicate*.
  #
  # The returned channels will close once `self` is closed and empty.
  #
  # Any exception raised while evaluating *predicate* will be passed
  # to the optional callback *on_error*, together with the value that
  # triggered the error.
  def select(
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &predicate : T -> Bool
  ) : Channel(T)
    Channel(T).new(buffer_size).tap { |stream|
      spawn(name: name) do
        loop do
          t = self.receive
          begin
            should_send = predicate.call(t)
            stream.send(t) if should_send
          rescue ex
            on_error.call(t, ex)
          end
        end
      rescue Channel::ClosedError
        stream.close
      end
    }
  end

  # Returns a channel which receives values received by `self`
  # that do **not** satisfy the given *predicate*.
  #
  # The returned channels will close once `self` is closed and empty.
  #
  # See `#select` for details on the exception handling strategy.
  def reject(
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &predicate : T -> Bool
  ) : Channel(T)
    self.select(name: name, buffer_size: buffer_size, on_error: on_error) { |v|
      !predicate.call(v)
    }
  end

  # Returns a tuple of two channels, one receiving values that satisfy
  # the given *predicate* and one receiving the remaining ones.
  #
  # The returned channels will close once `self` is closed and empty.
  #
  # See `#select` for details on the exception handling strategy.
  def partition(
    name = nil,
    buffer_size = 0,
    on_error = ->(t : T, ex : Exception) {},
    &predicate : T -> Bool
  ) : {Channel(T), Channel(T)}
    {Channel(T).new(buffer_size), Channel(T).new(buffer_size)}.tap { |pass, fail|
      spawn(name: name) do
        self.listen do |t|
          predicate.call(t) ? (pass.send(t)) : (fail.send(t))
        rescue ex
          on_error.call(t, ex)
        end
        pass.close
        fail.close
      end
    }
  end

  # Returns a channel that receives values in batches either every *size* values
  # received or every *interval*, if a batch has not been sent within the last *interval*.
  #
  # The returned channels will close once `self` is closed and empty.
  def batch(size : Int32, interval : Time::Span, name = nil, buffer_size = 0) : Channel(Enumerable(T))
    Channel(Enumerable(T)).new(buffer_size).tap { |stream|
      memory = Array(T).new(size)
      tick = Concur.every(interval) { nil }
      sent = false
      spawn(name: name) do
        loop do
          select
          when v = self.receive
            memory << v
            if memory.size >= size
              stream.send(memory.dup)
              memory.clear
              sent = true
            end
          when tick.receive
            unless sent
              stream.send(memory.dup)
              memory.clear
            end
            sent = false
          end
        end
      rescue Channel::ClosedError
        stream.send(memory.dup)
        stream.close
      end
    }
  end

  # Receives values from `self` and processes them via *block*.
  #
  # If no exceptions are raised while evaluating *block*, then the
  # statement returns once `self` is closed and empty.
  #
  # NOTE: This method runs on the current fiber.
  #
  # NOTE: If exceptions are not handled within *block*, then any exception
  # raised within the block will crash the calling fiber.
  def listen(&block : T -> _)
    loop do
      block.call(self.receive)
    rescue Channel::ClosedError
      break
    end
  end

  # Runs the given *block* for each value received from `self`.
  # The execution of the block takes place on a separate fiber.
  #
  # The fiber running the block will stop once `self` is closed and empty.
  #
  # NOTE: If exceptions are not handled within *block*, then any exception
  # raised within the block will crash the spawned fiber.
  def each(name = nil, &block : T -> _)
    spawn(name: name) do
      self.listen(&block)
    end
  end
end
