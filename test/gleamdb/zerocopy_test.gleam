import gleeunit/should
import gleam/option.{None, Some}
import gleam/list
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/index/ets as ets_index

pub fn zerocopy_binary_test() {
  let config = types.Config(
    parallel_threshold: 1000,
    batch_size: 100,
    prefetch_enabled: False,
    zero_copy_threshold: 5, // Trigger fallback serialization over 5 datoms
  )
  
  let assert Ok(db) = gleamdb.start_named("zerocopy_test_db", None)
  gleamdb.set_config(db, config)
  
  let _ = gleamdb.set_schema(db, "sensor/reading", fact.AttributeConfig(
    unique: False, component: False, retention: fact.All, cardinality: fact.Many, 
    check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory
  ))
  
  // Create 10 facts (exceeds zero_copy_threshold of 5)
  // use modern gleam int padding rather than list.range if it's deprecated, but list.range is fine for a quick test if we ignore the warning. Wait, I will use custom loop.
  let facts = gleamdb_create_facts(10, [])
  
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // Pull all from Entity 100. Should return PullRawBinary!
  let res = gleamdb.pull(db, fact.Uid(fact.EntityId(100)), gleamdb.pull_all())
  
  case res {
    types.PullRawBinary(bin) -> {
      // Assert that we successfully got a raw C-level payload
      let _dyn = ets_index.deserialize_term(bin)
      // If we reach here, it deserialized without crashing via erlang term_to_binary validation
      Nil
    }
    _ -> should.fail() // Should not follow standard PullMap path when threshold exceeded
  }
}

fn gleamdb_create_facts(n: Int, acc: List(fact.Fact)) -> List(fact.Fact) {
  case n {
    0 -> acc
    _ -> {
      let f = #(fact.uid(100), "sensor/reading", fact.Int(n))
      gleamdb_create_facts(n - 1, [f, ..acc])
    }
  }
}
