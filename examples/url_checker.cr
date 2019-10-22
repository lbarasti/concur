require "yaml"
require "http/client"
require "../src/concur"
extend Concur

get_urls = -> {
  YAML.parse(
    File.read("./examples/url_checker.yml")
  )["urls"].as_a.map(&.as_s)
}

successes, failures = flatten(every(2.seconds) {
  get_urls.call
}).map(workers = 2) { |url|
begin
  {url, HTTP::Client.get url}
rescue e
  {url, e}
end
}.partition { |(_, result)|
  case result
  when HTTP::Client::Response
    result.status.success? || result.status.redirection?
  else false
  end
}

successes
failures

sleep