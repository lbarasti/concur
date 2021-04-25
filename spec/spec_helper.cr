require "spec"
require "../src/concur"
extend Concur

Spec.override_default_formatter(Spec::VerboseFormatter.new)

def assert_elapsed(start_time, expected)
  (Time.utc - start_time).to_f.should be_close(expected, 1e-2)
end

def take(stream, n)
  (1..n).map { stream.receive }
end