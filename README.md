![GitHub release](https://img.shields.io/github/release/lbarasti/concur.svg)
![Build Status](https://github.com/lbarasti/concur/workflows/spec_and_docs/badge.svg)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Docs](https://img.shields.io/badge/docs-available-brightgreen.svg)](https://lbarasti.github.io/concur)

# concur

A collection of primitives for event-driven programming.

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

Check out the [API docs](https://lbarasti.com/concur/) for more details.

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
