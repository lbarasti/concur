require "../src/concur"

n = Future.new { 42 }
  .map { |v| v // 2 }
  .await!

pp n

raise Exception.new("Something went wrong") unless n == 21