require "yaml"
require "http/client"
require "../src/concur"
require "agent"
require "crt"
require "tablo"
extend Concur

record StatsCount, success : Hash(String, Int32), failure : Hash(String, Int32)

class Stats
  @success : Agent(Hash(String, Int32))
  @failure : Agent(Hash(String, Int32))

  def initialize
    @success = Agent.new Hash(String, Int32).new(0)
    @failure = Agent.new Hash(String, Int32).new(0)
  end
  def increment_success(url : String)
    @success.update { |success| success[url] += 1; success }
  end
  def increment_failure(url : String)
    @failure.update { |failure| failure[url] += 1; failure }
  end
  def get
    StatsCount.new(@success.get!, @failure.get!)
  end
end

get_urls = -> {
  YAML.parse(
    File.read("./url_checker.yml")
  )["urls"].as_a.map(&.as_s)
}

successes, failures = flatten(every(2.seconds) {
  get_urls.call
}).map(workers: 2) { |url|
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

stats = Stats.new
win = Crt::Window.new(24, 80)

successes.map { |result| stats.increment_success result[0] }
  .merge(failures.map { |result| stats.increment_failure result[0] })
  .listen { |v|
    count = stats.get
    urls = (count.success.keys + count.failure.keys).uniq
    data = urls.map { |url| [url, count.success[url] || 0, count.failure[url] || 0]}
    table = Tablo::Table.new(data) do |t|
      t.add_column("Url", width: 28) { |n| n[0] }
      t.add_column("Success") { |n| n[1] }
      t.add_column("Failure") { |n| n[2] }
    end
    win.clear
    win.print(0, 0, table.to_s)
    win.refresh
  }
