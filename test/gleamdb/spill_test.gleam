import gleeunit/should
import gleam/option.{Some, None}
import gleam/list
import gleam/int
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/q
import gleam/erlang/process
import gleam/io

pub fn disk_spilling_test() {
  // 1. Initialize DB with small memory limit to force spilling
  let config = types.Config(
    parallel_threshold: 1000,
    batch_size: 1, // Any tx older than 1 is eligible for eviction
    prefetch_enabled: False,
    zero_copy_threshold: 10000,
  )
  let assert Ok(db) = gleamdb.start_named("spill_test_db", None)
  gleamdb.set_config(db, config)
  
  // 2. Set schema to force LruToDisk eviction
  let config = fact.AttributeConfig(
    unique: False, component: False, retention: fact.All, 
    cardinality: fact.Many, check: None, composite_group: None, 
    layout: fact.Row, tier: fact.Disk, eviction: fact.LruToDisk
  )
  let assert Ok(_) = gleamdb.set_schema(db, "log/entry", config)

  // 3. Ingest Data (Batches to trigger lifecycle eviction)
  // Let's transact 3 separate batches to ensure `Tick` triggers eviction of older tx.
  let ingest_batch = fn(start, end) {
    let data = list.range(start, end)
      |> list.map(fn(i) {
        #(fact.deterministic_uid(i), "log/entry", fact.Str("log_" <> int.to_string(i)))
      })
    let assert Ok(_) = gleamdb.transact(db, data)
  }

  let _ = ingest_batch(1, 100)
  process.sleep(100) // Allow lifecycle actor to breathe
  let _ = ingest_batch(101, 200)
  process.sleep(100)
  let _ = ingest_batch(201, 300)
  process.sleep(100)

  // 4. Send manual Tick to trigger eviction if timer hasn't fired
  let assert Ok(_) = gleamdb.trigger_eviction(db)
  
  // 5. Query for data that should logically be on disk now
  // We query for item 50, which was in the first transaction and should be evicted from Memory.
  let query = q.new()
    |> q.where(q.v("e"), "log/entry", q.s("log_50"))
    |> q.to_clauses()
    
  let results = gleamdb.query(db, query)
  
  // Verify the engine seamlessly queried it from the underlying index (Mnesia)
  results.rows |> list.length() |> should.equal(1)
}
