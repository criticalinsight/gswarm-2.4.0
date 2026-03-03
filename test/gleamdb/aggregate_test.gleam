import gleeunit/should
import gleamdb/fact.{Int, Float, Str}
import gleamdb/algo/aggregate
import gleamdb/shared/types.{Sum, Count, Min, Max, Avg, Median}

pub fn sum_test() {
  let values = [Int(1), Int(2), Int(3)]
  aggregate.aggregate(values, Sum)
  |> should.equal(Ok(Int(6)))

  let floats = [Float(1.5), Float(2.5)]
  aggregate.aggregate(floats, Sum)
  |> should.equal(Ok(Float(4.0)))

  let mixed = [Int(1), Float(2.5)]
  aggregate.aggregate(mixed, Sum)
  |> should.equal(Ok(Float(3.5)))
  
  let empty = []
  aggregate.aggregate(empty, Sum)
  |> should.equal(Ok(Float(0.0))) // Sum of empty is 0.0 (as float to be safe? Or Int 0? Implementation used Float(0.0) initial accumulator? No, try_fold with Float(0.0))
}

pub fn count_test() {
  let values = [Int(1), Int(2), Int(3)]
  aggregate.aggregate(values, Count)
  |> should.equal(Ok(Int(3)))
  
  let empty = []
  aggregate.aggregate(empty, Count)
  |> should.equal(Ok(Int(0)))
}

pub fn min_max_test() {
  let values = [Int(10), Int(5), Int(20)]
  aggregate.aggregate(values, Min)
  |> should.equal(Ok(Int(5)))
  
  aggregate.aggregate(values, Max)
  |> should.equal(Ok(Int(20)))
  
  let strings = [Str("apple"), Str("banana"), Str("cherry")]
  aggregate.aggregate(strings, Min)
  |> should.equal(Ok(Str("apple")))
  
  aggregate.aggregate(strings, Max)
  |> should.equal(Ok(Str("cherry")))
}

pub fn avg_test() {
  let values = [Int(2), Int(4), Int(6)]
  aggregate.aggregate(values, Avg)
  |> should.equal(Ok(Float(4.0)))
  
  let floats = [Float(2.5), Float(7.5)]
  aggregate.aggregate(floats, Avg)
  |> should.equal(Ok(Float(5.0)))
}

pub fn median_test() {
  // Odd length
  let v1 = [Int(1), Int(5), Int(20)]
  aggregate.aggregate(v1, Median)
  |> should.equal(Ok(Int(5)))
  
  // Even length: (2 + 4) / 2 = 3.0
  let v2 = [Int(1), Int(2), Int(4), Int(5)]
  aggregate.aggregate(v2, Median)
  |> should.equal(Ok(Float(3.0)))
}
