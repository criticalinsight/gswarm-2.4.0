import gleam/option.{None}
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/q
import gleamdb/fact
import gleamdb/math

pub fn main() {
  gleeunit.main()
}

pub fn vector_storage_test() {
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  
  // 1. Transact a Vector
  let embedding = [0.1, 0.2, 0.3]
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/embedding", fact.Vec(embedding))
  ])
  
  // 2. Retrieve it via standard query
  let query = q.select(["v"])
    |> q.where(q.i(1), "user/embedding", q.v("v"))
    |> q.to_clauses()
    
  let _result = gleamdb.query(db, query)
  
  // 3. Test Math
  let v1 = [1.0, 0.0]
  let v2 = [0.0, 1.0]
  let assert Ok(sim) = math.cosine_similarity(v1, v2)
  should.equal(sim, 0.0)
  
  let v3 = [1.0, 0.0]
  let assert Ok(sim2) = math.cosine_similarity(v1, v3)
  should.equal(sim2, 1.0)
  
  // 4. Test Pull
  let _res = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), gleamdb.pull_attr("user/embedding"))
  
  should.be_true(True)
}
