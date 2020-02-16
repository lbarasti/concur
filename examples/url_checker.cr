require "yaml"
require "http/client"
require "../src/concur"
require "dataclass"
require "crt"
require "tablo"
extend Concur

abstract class StatsRequests; end;
dataclass Failure{url : String} < StatsRequests
dataclass Success{url : String} < StatsRequests
dataclass Get{channel : Channel(StatsCount)} < StatsRequests

dataclass StatsCount{success : Hash(String, Int32), failure : Hash(String, Int32)}
class Stats
  def initialize
    # TODO: read from DB
    @success = Hash(String, Int32).new(0)
    @failure = Hash(String, Int32).new(0)
    @comm = Channel(StatsRequests).new
    spawn do
      @comm.listen { |v|
        case v
        when Success
          @success[v.url] += 1
        when Failure
          @failure[v.url] += 1
        when Get
          v.channel.send StatsCount.new(@success, @failure)
        end
      }
    end
  end
  def increment_success(url : String)
    @comm.send Success.new(url)
  end
  def increment_failure(url : String)
    @comm.send Failure.new(url)
  end
  def get
    Channel(StatsCount).new.tap { |tmp|
      @comm.send Get.new(tmp)
    }.receive
  end
end

get_urls = -> {
  YAML.parse(
    File.read("./url_checker.yml")
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

stats = Stats.new
win = Crt::Window.new(24, 80)

merge(
  successes.map { |result|
    stats.increment_success result[0]
  },
  failures.map { |result|
    stats.increment_failure result[0]
  }
).listen { |v|
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
sleep