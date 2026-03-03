import gleeunit/should
import gleam/option.{None}
import gleam/dict
import gleam/list
import gleamdb/fact.{Str, Int}
import gleamdb/engine
import gleamdb/shared/types
import gleamdb/storage
import gleamdb/q
import gleamdb/raft
import gleamdb/vec_index
import gleamdb/index/art
import gleam/erlang/process

pub fn virtual_predicate_test() {
  // Define a dummy virtual adapter that returns static data
  // Predicate: "users_csv"
  // Args: [] (none)
  // Outputs: ["name", "age"]
  let users_csv = fn(_args: List(fact.Value)) -> List(List(fact.Value)) {
    [
      [Str("Alice"), Int(30)],
      [Str("Bob"), Int(25)],
    ]
  }

  let db_state = types.DbState(
    adapter: storage.ephemeral(),
    eavt: dict.new(),
    aevt: dict.new(),
    avet: dict.new(),
    bm25_indices: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: process.new_subject(),
    followers: [],
    is_distributed: False,
    ets_name: None,
    raft_state: raft.new([]),
    vec_index: vec_index.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.from_list([#("users_csv", users_csv)]),
    columnar_store: dict.new(),
    config: types.Config(parallel_threshold: 500, batch_size: 100, prefetch_enabled: False, zero_copy_threshold: 10000),
    query_history: [],
  )

  // Query: find users older than 28 from the virtual predicate
  // ?find ?name ?age . virtual("users_csv", [], [?name, ?age]) . ?age > 28
  let clauses = q.new()
    |> q.virtual("users_csv", [], ["name", "age"])
    |> q.filter(types.Gt(types.Var("age"), types.Val(Int(28))))
    |> q.to_clauses()

  let results = engine.run(db_state, clauses, [], None, None)
  
  should.equal(list.length(results.rows), 1)
  let assert [row] = results.rows
  should.equal(dict.get(row, "name"), Ok(Str("Alice")))
  should.equal(dict.get(row, "age"), Ok(Int(30)))
}
