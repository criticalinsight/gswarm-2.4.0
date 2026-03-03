import gleeunit/should
import gleam/option.{None}
import gleam/dict
import gleam/list
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine
import gleamdb/storage
import gleamdb/reactive
import gleamdb/raft
import gleamdb/vec_index
import gleamdb/index/art

pub fn engine_run_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    types.DbState(
      adapter: storage.ephemeral(),
      aevt: dict.new(),
      avet: dict.new(),
      bm25_indices: dict.new(),
      eavt: dict.new(),
      vec_index: vec_index.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
      raft_state: raft.new([]),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(parallel_threshold: 500, batch_size: 100, prefetch_enabled: False, zero_copy_threshold: 10000),
      query_history: [],
    )

  let query = [types.Positive(#(types.Var("e"), "name", types.Val(fact.Str("Alice"))))]
  let results = engine.run(state, query, [], None, None)
  should.equal(list.length(results.rows), 0)
}

pub fn pull_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    types.DbState(
      adapter: storage.ephemeral(),
      aevt: dict.new(),
      avet: dict.new(),
      bm25_indices: dict.new(),
      eavt: dict.new(),
      vec_index: vec_index.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
      raft_state: raft.new([]),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(parallel_threshold: 500, batch_size: 100, prefetch_enabled: False, zero_copy_threshold: 10000),
      query_history: [],
    )
  let res = engine.pull(state, fact.Uid(fact.EntityId(1)), [types.Wildcard])
  let assert types.PullMap(m) = res
  should.equal(dict.size(m), 0)
}
