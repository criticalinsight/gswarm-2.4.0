import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import gleam/int
import gleam/float
import gleamdb/algo/aggregate
import gleamdb/algo/bloom
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/erlang/process
import gleamdb
import gleamdb/fact.{type Eid, Uid, Lookup}
import gleamdb/shared/types.{type BodyClause, type DbState, type QueryResult}
import gleamdb/storage.{type StorageAdapter}
import gleamdb/engine.{type PullPattern, type PullResult, Map}
import gleamdb/vec_index

pub type ShardedDb {
  ShardedDb(
    shards: Dict(Int, gleamdb.Db),
    shard_count: Int,
    cluster_id: String
  )
}

pub const mirror_shard_id = 99

/// Start a sharded database cluster.
pub fn start_sharded(
  cluster_id: String,
  shard_count: Int,
  adapter: Option(StorageAdapter),
) -> Result(ShardedDb, String) {
  let self = process.new_subject()

  // Spawn shard startups in parallel
  int.range(from: 0, to: shard_count, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.each(fn(i) {
    process.spawn(fn() {
      let shard_cluster_id = cluster_id <> "_s" <> string.inspect(i)
      let res = case gleamdb.start_distributed(shard_cluster_id, adapter) {
        Ok(db) -> Ok(#(i, db))
        Error(e) ->
          Error(
            "Failed to start shard "
            <> string.inspect(i)
            <> ": "
            <> string_inspect_actor_error(e),
          )
      }
      process.send(self, res)
    })
  })

  // Gather results
  let shards =
    int.range(from: 0, to: shard_count, with: [], run: fn(acc, _) {
      case process.receive(self, 600_000) {
        Ok(res) -> [res, ..acc]
        Error(_) -> [Error("Timeout starting shards"), ..acc]
      }
    })
    |> list.try_map(fn(x) { x })

  case shards {
    Ok(s) -> {
      Ok(ShardedDb(
        shards: dict.from_list(s),
        shard_count: shard_count,
        cluster_id: cluster_id,
      ))
    }
    Error(e) -> Error(e)
  }
}

/// Start a sharded database cluster in local (named) mode.
pub fn start_local_sharded(
  cluster_id: String,
  shard_count: Int,
  adapter: Option(StorageAdapter),
) -> Result(ShardedDb, String) {
  let self = process.new_subject()

  // Spawn shard startups in parallel
  int.range(from: 0, to: shard_count, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.each(fn(i) {
    process.spawn(fn() {
      let shard_cluster_id = cluster_id <> "_s" <> string.inspect(i)
      let res = case gleamdb.start_named(shard_cluster_id, adapter) {
        Ok(db) -> Ok(#(i, db))
        Error(e) ->
          Error(
            "Failed to start local shard "
            <> string.inspect(i)
            <> ": "
            <> string_inspect_actor_error(e),
          )
      }
      process.send(self, res)
    })
  })

  // Gather results
  let shards =
    int.range(from: 0, to: shard_count, with: [], run: fn(acc, _) {
      case process.receive(self, 300_000) {
        Ok(res) -> [res, ..acc]
        Error(_) -> [Error("Timeout starting shards"), ..acc]
      }
    })
    |> list.try_map(fn(x) { x })

  case shards {
    Ok(s) -> {
      Ok(ShardedDb(
        shards: dict.from_list(s),
        shard_count: shard_count,
        cluster_id: cluster_id,
      ))
    }
    Error(e) -> Error(e)
  }
}

/// Ingest facts into the sharded database in parallel.
/// Routing is determined by hashing the Entity ID (Eid).
pub fn transact(db: ShardedDb, facts: List(fact.Fact)) -> Result(List(DbState), String) {
  // Group facts by shard
  let grouped = list.fold(facts, dict.new(), fn(acc, f) {
    let shard_id = get_shard_id(f.0, db.shard_count)
    let shard_facts = dict.get(acc, shard_id) |> result.unwrap([])
    dict.insert(acc, shard_id, [f, ..shard_facts])
  })

  let grouped_list = dict.to_list(grouped)
  case grouped_list {
    [] -> Ok([])
    _ -> {
      let self = process.new_subject()

      // Scatter
      list.each(grouped_list, fn(pair) {
        let #(shard_id, shard_facts) = pair
        process.spawn(fn() {
          let assert Ok(shard_db) = dict.get(db.shards, shard_id)
          let res = case gleamdb.transact(shard_db, shard_facts) {
            Ok(state) -> Ok(state)
            Error(e) -> Error("Shard " <> string.inspect(shard_id) <> " transact failed: " <> e)
          }
          process.send(self, res)
        })
      })

      // Gather
      int.range(from: 0, to: list.length(grouped_list), with: [], run: fn(acc, _) {
        let res = case process.receive(self, 5000) {
          Ok(res) -> res
          Error(_) -> Error("Timeout waiting for shard")
        }
        [res, ..acc]
      })
      |> list.try_map(fn(x) { x })
    }
  }
}

/// Transact on a specific shard regardless of entity hashing.
pub fn transact_shard(db: ShardedDb, shard_id: Int, facts: List(fact.Fact)) -> Result(DbState, String) {
  case dict.get(db.shards, shard_id) {
    Ok(shard_db) -> gleamdb.transact(shard_db, facts)
    Error(_) -> Error("Shard " <> string.inspect(shard_id) <> " not found")
  }
}

/// Query the sharded database (Parallel Scatter-Gather).
/// Warning: This performs a full scan across all shards.
pub fn query(db: ShardedDb, clauses: List(BodyClause)) -> QueryResult {
  query_at(db, clauses, option.None, option.None)
}

/// Query the sharded database at a specific temporal basis.
pub fn query_at(
  db: ShardedDb,
  clauses: List(BodyClause),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> QueryResult {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let res = engine.run(
        gleamdb.get_state(shard_db),
        clauses,
        [],
        as_of_tx,
        as_of_valid,
      )
      process.send(self, res)
    })
  })

  // Gather
  int.range(
    from: 0,
    to: list.length(shard_list),
    with: types.QueryResult(
      rows: [],
      metadata: types.QueryMetadata(
        tx_id: option.None,
        valid_time: option.None,
        execution_time_ms: 0,
        shard_id: option.None,
        aggregates: dict.new(),
      ),
    ),
    run: fn(acc, _) {
      let res =
        process.receive(self, 5000)
        |> result.unwrap(types.QueryResult(
          rows: [],
          metadata: types.QueryMetadata(
            tx_id: option.None,
            valid_time: option.None,
            execution_time_ms: 0,
            shard_id: option.None,
            aggregates: dict.new(),
          ),
        ))

      let merged_metadata = types.QueryMetadata(
        tx_id: case acc.metadata.tx_id, res.metadata.tx_id {
          option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
          option.Some(_), option.None -> acc.metadata.tx_id
          option.None, option.Some(_) -> res.metadata.tx_id
          option.None, option.None -> option.None
        },
        valid_time: case acc.metadata.valid_time, res.metadata.valid_time {
          option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
          option.Some(_), option.None -> acc.metadata.valid_time
          option.None, option.Some(_) -> res.metadata.valid_time
          option.None, option.None -> option.None
        },
        execution_time_ms: acc.metadata.execution_time_ms
        + res.metadata.execution_time_ms,
        shard_id: acc.metadata.shard_id,
        aggregates: dict.merge(acc.metadata.aggregates, res.metadata.aggregates),
      )

      let all_rows = list.append(acc.rows, res.rows)
      
      case dict.size(merged_metadata.aggregates) > 0 {
        True -> {
           let rows = coordinate_reduce(all_rows, merged_metadata.aggregates)
           types.QueryResult(rows: rows, metadata: merged_metadata)
        }
        False -> types.QueryResult(rows: all_rows, metadata: merged_metadata)
      }
    },
  )
}

/// Perform a Bloom Filter Optimized distributed join.
/// This runs in two passes:
/// 1. Probe: Executes the probe clauses to identify join keys.
/// 2. Build: Executes the build clauses on shards using a Bloom filter of identified keys.
pub fn bloom_query(
  db: ShardedDb,
  join_var: String,
  probe_clauses: List(BodyClause),
  build_clauses: List(BodyClause),
) -> QueryResult {
  // Pass 1: Run probe_clauses globally to find join keys
  let probe_res = query(db, probe_clauses)

  // Build bloom filter from join_var values
  let keys =
    list.fold(probe_res.rows, [], fn(acc, row) {
      case dict.get(row, join_var) {
        Ok(val) -> [fact.to_string(val), ..acc]
        Error(_) -> acc
      }
    })
    |> list.unique()

  // Use a size appropriate for the key count, min 1024 bits
  let filter_size = int.max(1024, list.length(keys) * 10)
  let filter =
    list.fold(keys, bloom.new(filter_size, 3), fn(f, k) { bloom.insert(f, k) })

  // Pass 2: Run build_clauses globally, providing the bloom filter
  let optimized_build = [types.BloomFilter(join_var, filter), ..build_clauses]
  let build_res = query(db, optimized_build)

  // Pass 3: Final join in coordinator
  let final_rows =
    list.fold(probe_res.rows, [], fn(acc, probe_row) {
      let probe_val = dict.get(probe_row, join_var)
      let matching_build =
        list.filter(build_res.rows, fn(build_row) {
          dict.get(build_row, join_var) == probe_val
        })

      list.map(matching_build, fn(br) { dict.merge(probe_row, br) })
      |> list.append(acc)
    })

  types.QueryResult(
    rows: final_rows,
    metadata: types.QueryMetadata(
      tx_id: case probe_res.metadata.tx_id, build_res.metadata.tx_id {
        option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
        option.Some(_), option.None -> probe_res.metadata.tx_id
        option.None, option.Some(_) -> build_res.metadata.tx_id
        option.None, option.None -> option.None
      },
      valid_time: case
        probe_res.metadata.valid_time,
        build_res.metadata.valid_time
      {
        option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
        option.Some(_), option.None -> probe_res.metadata.valid_time
        option.None, option.Some(_) -> build_res.metadata.valid_time
        option.None, option.None -> option.None
      },
      execution_time_ms: probe_res.metadata.execution_time_ms
      + build_res.metadata.execution_time_ms,
      shard_id: option.None,
      aggregates: dict.merge(
        probe_res.metadata.aggregates,
        build_res.metadata.aggregates,
      ),
    ),
  )
}

fn coordinate_reduce(rows: List(Dict(String, fact.Value)), aggregates: Dict(String, types.AggFunc)) -> List(Dict(String, fact.Value)) {
  case rows {
    [] -> []
    [first_row, ..] -> {
      // 1. Identify grouping variables (those NOT in aggregates)
      let grouping_vars = dict.keys(first_row) |> list.filter(fn(k) { !dict.has_key(aggregates, k) })
      
      // 2. Group by grouping variables
      let grouped = list.fold(rows, dict.new(), fn(acc, row) {
        let group_key = list.map(grouping_vars, fn(v) { dict.get(row, v) |> result.unwrap(fact.Int(0)) })
        let members = dict.get(acc, group_key) |> result.unwrap([])
        dict.insert(acc, group_key, [row, ..members])
      })
      
      // 3. For each group, reduce aggregate variables
      dict.to_list(grouped)
      |> list.map(fn(pair) {
        let #(key_vals, members) = pair
        let base_row = list.zip(grouping_vars, key_vals) |> dict.from_list()
        
        dict.to_list(aggregates)
        |> list.fold(base_row, fn(row_acc, agg_pair) {
          let #(var, func) = agg_pair
          let shard_vals = list.filter_map(members, fn(m) { dict.get(m, var) })
          
          let final_val = case func {
            types.Sum | types.Count -> {
               // FOR SUM and COUNT, the secondary reduction is a SUM of shard results.
               gleamdb_aggregate(shard_vals, types.Sum) |> result.unwrap(fact.Int(0))
            }
            types.Min -> gleamdb_aggregate(shard_vals, types.Min) |> result.unwrap(fact.Int(0))
            types.Max -> gleamdb_aggregate(shard_vals, types.Max) |> result.unwrap(fact.Int(0))
            _ -> {
               // Average/Median are not perfectly supported in this pass without more metadata.
               // We return the first one or a placeholder to avoid crash.
               list.first(shard_vals) |> result.unwrap(fact.Int(0))
            }
          }
          dict.insert(row_acc, var, final_val)
        })
      })
    }
  }
}

// Redirect to avoid name clash
fn gleamdb_aggregate(vals, func) {
  aggregate.aggregate(vals, func)
}

/// Pull an entity in parallel across all shards.
pub fn pull(db: ShardedDb, eid: Eid, pattern: PullPattern) -> PullResult {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let res = gleamdb.pull(shard_db, eid, pattern)
      process.send(self, res)
    })
  })

  // Gather
  int.range(
    from: 0,
    to: list.length(shard_list),
    with: Map(dict.new()),
    run: fn(acc, _) {
      let res = process.receive(self, 5000) |> result.unwrap(Map(dict.new()))
      merge_pull_results(acc, res)
    },
  )
}

/// Perform a global vector similarity search across all shards.
/// Phase 50: Distributed V-Link.
pub fn global_vector_search(
  db: ShardedDb,
  query_vec: List(Float),
  threshold: Float,
  k: Int,
) -> List(vec_index.SearchResult) {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let db_state = gleamdb.get_state(shard_db)
      let res = vec_index.search(db_state.vec_index, query_vec, threshold, k)
      process.send(self, res)
    })
  })

  // Gather
  int.range(from: 0, to: list.length(shard_list), with: [], run: fn(acc, _) {
    let shard_results = process.receive(self, 5000) |> result.unwrap([])
    list.append(acc, shard_results)
  })
  // Reduce (Global Top-K)
  |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
  |> list.take(k)
}

/// Stop the sharded database.
pub fn stop(db: ShardedDb) -> Nil {
  let shard_list = dict.to_list(db.shards)
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    let assert Ok(pid) = process.subject_owner(shard_db)
    process.unlink(pid)
    process.kill(pid)
  })
}

fn merge_pull_results(a: PullResult, b: PullResult) -> PullResult {
  case a, b {
    Map(d1), Map(d2) -> Map(dict.merge(d1, d2))
    _, Map(_) -> b
    Map(_), _ -> a
    _, _ -> a
  }
}

fn get_shard_id(eid: Eid, shard_count: Int) -> Int {
  case eid {
    Uid(fact.EntityId(id)) -> id % shard_count
    Lookup(#(_, val)) -> fact.phash2(val) % shard_count
  }
}

fn string_inspect_actor_error(e: actor.StartError) -> String {
  string.inspect(e)
}
