# A Future represents a value which may or may not *currently* be available, but will be
# available at some point, or an exception if that value could not be made available.
class Future(T)
  class EmptyError < Exception
  end

  class Timeout < Exception
  end

  @value : T? = nil
  @error : Exception? = nil

  def initialize(&block : -> T)
    @value_ch = Channel(T).new(1)
    @error_ch = Channel(Exception).new(1)

    spawn do
      result = block.call
      @value_ch.send result
    rescue exception
      @error_ch.send exception
    end
  end

  # Awaits the completion of the future and returns either a value or an exception.
  def await : T | Exception
    unless done?
      select
      when res = @value_ch.receive?
        @value = res if res
      when err = @error_ch.receive?
        @error = err if err
      end
      @value_ch.close
      @error_ch.close
    end
    @error ? @error.not_nil! : @value.not_nil!
  end

  # Awaits the completion of the future and either returns the computed value
  # or raises an exception.
  def await! : T
    case res = await
    when T
      res
    else
      raise res
    end
  end

  # Same as `#await`, but returns a `Timeout` exception if the given `t` expires.
  def await(t : Time::Span) : T | Exception
    unless done?
      select
      when timeout(t)
        return Timeout.new
      when res = @value_ch.receive?
        @value = res if res
      when err = @error_ch.receive?
        @error = err if err
      end
      @value_ch.close
      @error_ch.close
    end
    @error ? @error.not_nil! : @value.not_nil!
  end

  # Same as `#await!`, but raises a `Timeout` exception if the given `t` expires.
  def await!(t : Time::Span) : T
    case res = await(t)
    when T
      res
    else
      raise res
    end
  end

  # Returns `true` if the future has completed - either with a value or an exception.
  # Returns `false` otherwise.
  def done?
    @value_ch.closed?
  end

  # Creates a new future by applying a function to the successful result of this future,
  # and returns the result of the function as the new future.
  #
  # If this future is completed with an exception then the new future will also contain this exception.
  def flat_map(&block : T -> Future(K)) : Future(K) forall K
    map { |value|
      block.call(value).await!
    }
  end

  # Creates a new future with one level of nesting flattened.
  def flatten
    flat_map { |fut| fut }
  end

  # Creates a new future by applying a function to the successful result of this future.
  #
  # If this future is completed with an exception then the new future will also contain this exception.
  def map(&block : T -> K) : Future(K) forall K
    transform { |res|
      case res
      when T
        block.call(res)
      else
        raise res
      end
    }
  end

  # Creates a new Future which is completed with this Future's result if
  # that conforms to type `typ` or a `TypeCastError` otherwise.
  def map_to(typ : Object.class)
    map { |value| typ.cast(value) }
  end

  # Applies the side-effecting function to the result of this future, and returns a new future
  # with the result of this future.
  #
  # This method allows one to enforce that the callbacks are executed in a specified order.
  # Note: if one of the chained `on_complete` callbacks throws an exception, that exception is not
  # propagated to the subsequent `on_complete` callbacks. Instead, the subsequent `on_complete` callbacks
  # are given the original value of this future.
  def on_complete(&block : (T | Exception) -> _) : Future(T)
    transform { |res|
      begin
        block.call(res)
      rescue
        # no-op
      end
      case res
      when T; res
      else raise res
      end
    }
  end

  # Applies the side-effecting function to the result of this future if it was successful, and
  # returns a new future with the result of this future.
  #
  # WARNING: Will not be called if this future is never completed or if it is completed with an error.
  def on_success(&block : T -> _) : Future(T)
    on_complete { |res|
      case res
      when T
        block.call(res)
      end
    }
  end

  # Applies the side-effecting function to the result of this future if it raised an error, and
  # returns a new future with the result of this future.
  #
  # WARNING: Will not be called if this future is never completed or if it is completed with success.
  def on_error(&block : Exception -> _) : Future(T)
    on_complete { |res|
      case res
      when Exception
        block.call(res)
      end
    }
  end

  # Creates a new future that will handle any matching throwable that this future might contain.
  # If there is no match, or if this future contains a valid result then the new future will contain the same.
  def recover(&block : Exception -> T) : Future(T)
    transform { |res|
      case res
      when T
        res
      else
        block.call(res)
      end
    }
  end

  # Creates a new future by filtering the value of the current future with a predicate.
  #
  # If the current future contains a value which satisfies the predicate, the new future will also hold that value.
  # Otherwise, the resulting future will fail with a `EmptyError`.
  # If the current future fails, then the resulting future also fails.
  def select(&block : T -> Bool) : Future(T)
    map { |value|
      if block.call(value)
        value
      else
        raise EmptyError.new
      end
    }
  end

  # Creates a new Future by applying the specified function to the result of this Future.
  #
  # If there is any non-fatal exception thrown when 'block' is applied then that exception
  # will be propagated to the resulting future.
  def transform(&block : (T | Exception) -> K) : Future(K) forall K
    Future.new {
      block.call(self.await)
    }
  end

  # Creates a new future holding the result of `block` applied to the tuple of values from two futures.
  def zip(other : Future(K), &block : (T, K) -> W) : Future(W) forall K, W
    flat_map { |t| other.map { |k| block.call(t, k) } }
  end
end
