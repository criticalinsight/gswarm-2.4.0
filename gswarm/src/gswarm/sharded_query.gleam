import gleam/int
import gleam/list
import gleam/dict
import gleam/option
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/engine.{type PullResult}
import gleamdb/shared/types.{type BodyClause, type QueryResult}
import gleamdb/sharded
import gswarm/node.{type ShardedContext}
import gswarm/shard_manager
import gswarm/registry_actor

/// Sharded Query Engine (Phase 40).
/// Rich Hickey: "Unifying independent shards into a single logical model."

/// Parallel Query: Executes the same query on all shards and merges results.
/// Prunes shards using Bloom filters if a specific market_id is identified in the clauses.
pub fn query_all(ctx: ShardedContext, clauses: List(BodyClause)) -> QueryResult {
  // Identify if any clause targets a specific market_id for optimization
  let target_market_id = list.find_map(clauses, fn(c) {
    case c {
      types.Positive(#(types.Val(fact.Str(mid)), "market/id", _)) -> Ok(mid)
      types.Positive(#(_, "market/id", types.Val(fact.Str(mid)))) -> Ok(mid)
      _ -> Error(Nil)
    }
  })

  case target_market_id {
    Ok(mid) -> {
      // Fetch live registry from actor (Phase 43) for Bloom pruning
      let registry_reply = process.new_subject()
      process.send(ctx.registry_actor, registry_actor.GetRegistry(registry_reply))
      let registry = case process.receive(registry_reply, 100) {
        Ok(reg) -> reg
        Error(_) -> ctx.registry
      }
      
      let empty_res = types.QueryResult(
        rows: [], 
        metadata: types.QueryMetadata(tx_id: option.None, valid_time: option.None, execution_time_ms: 0, shard_id: option.None, aggregates: dict.new())
      )
      
      let shard_id = shard_manager.get_shard_id(mid, registry.shard_count)
      case shard_manager.market_might_exist(registry, mid) {
        True -> {
          case dict.get(ctx.db.shards, shard_id) {
            Ok(db) -> gleamdb.query(db, clauses)
            Error(_) -> empty_res
          }
        }
        False -> empty_res
      }
    }
    Error(_) -> sharded.query(ctx.db, clauses)
  }
}

/// Query sharded data since a specific transaction.
/// This uses the promoted Core temporal optimization with negative basis for 'since' semantics.
pub fn query_since(ctx: ShardedContext, clauses: List(BodyClause), tx: Int) -> QueryResult {
  sharded.query_at(ctx.db, clauses, option.Some(-tx), option.None)
}

/// Parallel Pull: Pulls an entity across all shards.
pub fn pull_all(ctx: ShardedContext, e_id: Int) -> PullResult {
  let eid = fact.Uid(fact.EntityId(e_id))
  let pattern = gleamdb.pull_all()
  sharded.pull(ctx.db, eid, pattern)
}

/// Helper: Find which shard contains a specific market_id and return its DB.
pub fn get_market_db(ctx: ShardedContext, market_id: String) -> Result(gleamdb.Db, String) {
  let shard_id = shard_manager.get_shard_id(market_id, ctx.db.shard_count)
  
  case dict.get(ctx.db.shards, shard_id) {
    Ok(db) -> Ok(db)
    Error(_) -> Error("Shard " <> int.to_string(shard_id) <> " not found")
  }
}
