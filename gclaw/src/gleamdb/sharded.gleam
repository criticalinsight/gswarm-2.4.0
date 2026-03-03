import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import gleam/int
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/erlang/process
import gleamdb
import gleamdb/fact.{type Eid, Uid, Lookup}
import gleamdb/shared/types.{type BodyClause, type DbState, type QueryResult}
import gleamdb/storage.{type StorageAdapter}
import gleamdb/engine.{type PullPattern, type PullResult, Map}

pub type ShardedDb {
  ShardedDb(
    shards: Dict(Int, gleamdb.Db),
    shard_count: Int,
    cluster_id: String
  )
}

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
          ),
        ))

      types.QueryResult(
        rows: list.append(acc.rows, res.rows),
        metadata: types.QueryMetadata(
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
        ),
      )
    },
  )
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
