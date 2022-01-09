require "../src/concur"
include Concur

pp source(Random.new) { |gen| {gen, {gen.rand, gen.rand}} }
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
  .take 1
