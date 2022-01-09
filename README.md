![GitHub release](https://img.shields.io/github/release/lbarasti/concur.svg)
![Build Status](https://github.com/lbarasti/concur/workflows/spec_and_docs/badge.svg)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Docs](https://img.shields.io/badge/docs-available-brightgreen.svg)](https://lbarasti.github.io/concur)

# concur

Concur is organised around two APIs:
* A `Future` API to deal with asynchronous computations
* An augmented `Channel` API with primitives to simplify event-driven programming.

## Installation

Add the dependency to your `shard.yml` and run `shards install`:

  ```yaml
  dependencies:
    concur:
      github: lbarasti/concur
  ```

## Usage

```crystal
require "concur"
```

### Using Future
You can use `Future` to wrap asynchronous computations that might fail.
```crystal
f = Future.new {
  sleep 2 # a placeholder for some expensive computation or for a lengthy IO operation
  "Success!"
}

f.await # => "Success!"
```
If you want to keep on manipulating the result of a future in a separate fiber, then you can rely on `Future`'s instance methods.

For example, given a future `f`, you can apply a function to the wrapped value with `#map`, filter it with `#select` and recover from failure with `#recover`

```crystal
f.map { |v| v.downcase }
  .select { |v| v.size < 3 }
  .recover { "default_key" }
```

Here is a contrived example to showcase some other common methods.

You can combine the result of two Futures into one with `#zip`:

```crystal
author_f : Future(User) = db.user_by_id(1)
reviewer_f : Future(User) = db.user_by_id(2)

permission_f : Future(Bool) = author_f.zip(reviewer_f) { |author, reviewer|
  author.has_reviewer?(reviewer) 
}
```

You can use `#flat_map` to avoid nesting futures:

```crystal
content_f : Future(Content) = permission_f
  .flat_map { |reviewer_is_allowed|
    if reviewer_is_allowed
      db.content_by_user(1) # => Future(Content)
    else
      raise NotAllowedError.new
    end
  }
```

And perform side effects with `#on_success` and `#on_error`.

```crystal
content_f
  .on_success { |content|
    reviewer_f.await!.email(content)
  }
  .on_error { |ex| log_error(ex) }
```

### Using Channel
Concur tries to increase the usability of `Channel` by adding a collection of transformation and callback methods to its API.

#### Sources: the beginning and the end
A Concur flow usually starts with a *source*.

```crystal
s1 = Concur.source(1..10) # returns a Channel(Int32) receiving each value of the range

s2 = Concur.source(initial_state: 0) { |state| (state + 1)**2 } # returns a Channel(Int32) receiving the values (i + 1)^2 for i = 0,1,...

s3 = Concur.every(1.second) { Time.utc } # returns a Channel(Time) receiving a timestamp approximately every second
```

Sources can also be built by simply defining a channel and having some fiber send values to it. For example, suppose you want your application to react to some keyboard event
that lets you register a callback:

```crystal
s4 = Channel(KeyboardEvent).new
keybord.on_keypress { |event| s4.send event }
```

Now that we have some sources, we can leverage Concur's API to materialise them or define some callbacks that will run every
time the channel receives a value.

```crystal
s1.listen { |v| puts v } # prints values from 1 to 10

s2.take(3) # => [1, 4, 25]

s3.each { |time|
  puts "you're living in the past" if time.year < 2022
}
```

#### Sources: the middle
We've seen how we can create a source and how we can *consume* it. Let's now look at how we can transform it.

Here is an example where we merge two event streams, batch them, process them into a new state and then persist that.

```crystal
keypress = Channel(KeyboardEvent).new
mouse_click = Channel(MouseEvent).new

# persist the state of the system every 5 events or every second,
# whichever happens first
keypress.merge(mouse_click)
  .batch(size: 5, interval: 1.seconds)
  .scan({"", {0,0}}) { |state, events|
    events.reduce(state) { |s, e|
      case e
      in MouseEvent
        {s[0], e.pos}
      in KeyboardEvent
        {s[0] + e.key, s[1]}
      end
    }
  }.each { |state| persist(state) }
```

Concur also lets you spin off concurrent computations very easily. Here is an example
where we let 4 workers compute the distance of a 2D point from the origin of a Cartesian plane.
We then produce an estimate of the constant Pi and look at how many iterations it took the process
to generate 10 consecutive estimates with a relative error of less than `1e-5`.

```crystal
source(Random.new) { |gen| {gen, {gen.rand, gen.rand}} }
  .map(workers: 4) { |(x,y)| x**2 + y**2 }
  .scan({0, 0}) { |acc, v|
    v <= 1 ? {acc[0] + 1, acc[1]} : {acc[0], acc[1] + 1}
  }.map { |(inner, outer)| 4 * inner / (inner + outer)}
  .zip(source(1..)) { |estimate, iteration| {iteration, estimate} }
  .batch(10, 1.second)
  .select { |estimates|
    estimates.all? { |(i, e)|
      (e - Math::PI).abs / Math::PI < 1e-5
    }
  }.flat_map { |estimates| estimates.map(&.first) }
  .take 1 # => [235191]
```

Check out the [API docs](https://lbarasti.com/concur/) and the `/examples` for more details.

## Development

Run `shards install` to install the project dependencies. You can then run `crystal spec` to verify that all the tests are passing.

## Contributing

1. Fork it (<https://github.com/lbarasti/concur/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [lbarasti](https://github.com/lbarasti) - creator and maintainer
