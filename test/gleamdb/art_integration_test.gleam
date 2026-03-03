import gleam/option.{None}
import gleam/dict
import gleam/list
import gleam/result
import gleamdb/fact
import gleamdb/transactor
import gleamdb/storage
import gleamdb/engine
import gleamdb/shared/types
import gleeunit/should

pub fn art_integration_test() {
  let assert Ok(db) = transactor.start(gleamdb_storage_memory())
  
  // 1. Insert Data
  let facts = [
    #(fact.deterministic_uid("1"), "name", fact.Str("Alice")),
    #(fact.deterministic_uid("2"), "name", fact.Str("Alan")),
    #(fact.deterministic_uid("3"), "name", fact.Str("Bob")),
    #(fact.deterministic_uid("4"), "name", fact.Str("Alex")),
    #(fact.deterministic_uid("5"), "city", fact.Str("London")),
  ]
  
  let assert Ok(_) = transactor.transact(db, facts)
  
  // 2. Query with StartsWith (Filter mode - bound variable)
  // Find entities with name starting with "Al"
  let clause = types.Positive(#(types.Var("e"), "name", types.Var("n")))
  let filter = types.StartsWith("n", "Al")
  
  let state = transactor.get_state(db)
  let results = engine.run(state, [clause, filter], [], None, None)
  
  let names = list.map(results.rows, fn(ctx) {
    let assert Ok(fact.Str(n)) = dict.get(ctx, "n")
    n
  })

  // Should find Alice, Alan, Alex (3)

  // Should find Alice, Alan, Alex (3)
  list.length(results.rows) |> should.equal(3)
  
  list.contains(names, "Alice") |> should.be_true
  list.contains(names, "Alan") |> should.be_true
  list.contains(names, "Alex") |> should.be_true
  list.contains(names, "Bob") |> should.be_false
  
  // 3. Query with StartsWith (Generator mode - unbound variable)
  // Find all values starting with "Lon"
  let gen_filter = types.StartsWith("city_name", "Lon")
  let results_gen = engine.run(state, [gen_filter], [], None, None)
  
  list.length(results_gen.rows) |> should.equal(1)
  let assert Ok(fact.Str("London")) = dict.get(list.first(results_gen.rows) |> result.unwrap(dict.new()), "city_name")
}

fn gleamdb_storage_memory() {
  // Mock storage adapter
  storage.ephemeral()
}
