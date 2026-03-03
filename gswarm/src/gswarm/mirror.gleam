import gleam/erlang/process.{type Subject}
import gleam/dict
import gleam/list
import gleam/result
import gleam/io
import gleam/float
import gswarm/leaderboard.{type Stats}
import gswarm/amka_domain
import gleamdb
import gleamdb/fact
import gleamdb/sharded
import gleamdb/shared/types

pub type State {
  State(
    db: sharded.ShardedDb,
    mirrored_trades: dict.Dict(String, Int), // trader_id -> last_mirrored_timestamp
    alpha_threshold: Float
  )
}

pub fn start(db: sharded.ShardedDb, lb: Subject(leaderboard.Message)) {
  process.spawn(fn() {
    let self = process.new_subject()
    let state = State(db: db, mirrored_trades: dict.new(), alpha_threshold: 1.0)
    process.send(lb, leaderboard.Subscribe(self))
    
    loop(state, self)
  })
}

fn loop(state: State, self: Subject(leaderboard.Stats)) {
  case process.receive(self, 60_000) {
    Ok(stats) -> {
       let new_state = handle_stats(state, stats)
       loop(new_state, self)
    }
    Error(_) -> loop(state, self)
  }
}

fn handle_stats(state: State, stats: Stats) -> State {
    // 1. Identify if this is a "Institutional Insider" (Query DB)
    let assert Ok(primary_db) = dict.get(state.db.shards, 0)
    let tid = fact.phash2(stats.trader_id)
    let query = [
        types.Positive(#(types.Val(fact.Ref(fact.EntityId(tid))), "trader/behavioral_tag", types.Val(fact.Str("Institutional Insider"))))
    ]
    
    let results = gleamdb.query(primary_db, query)
    case list.is_empty(results.rows) {
        False -> {
            // Institutional Insider identified!
            case list.first(stats.recent_activity) {
                Ok(activity) -> {
                    let last_ts = dict.get(state.mirrored_trades, stats.trader_id) |> result.unwrap(0)
                    case activity.timestamp > last_ts {
                        True -> {
                            mirror_trade(state, stats, activity)
                            State(..state, mirrored_trades: dict.insert(state.mirrored_trades, stats.trader_id, activity.timestamp))
                        }
                        False -> state
                    }
                }
                Error(_) -> state
            }
        }
        True -> state
    }
}

fn mirror_trade(state: State, stats: Stats, activity: amka_domain.TradeActivity) {
    let weight = stats.roi *. 10.0 // Simplified Alpha weight
    let mirror_size = activity.size *. float.max(weight, 1.0)
    
    io.println("🚀 Mirror Oracle: Following " <> stats.trader_id <> " | Weight: " <> float.to_string(weight))
    
    let mirror_facts = [
        #(fact.deterministic_uid("mirror_" <> stats.trader_id <> "_" <> float.to_string(mirror_size)), "mirror/source", fact.Str(stats.trader_id)),
        #(fact.deterministic_uid("mirror_" <> stats.trader_id <> "_" <> float.to_string(mirror_size)), "mirror/size", fact.Float(mirror_size)),
        #(fact.deterministic_uid("mirror_" <> stats.trader_id <> "_" <> float.to_string(mirror_size)), "mirror/market", fact.Str(activity.market_slug)),
        #(fact.deterministic_uid("mirror_" <> stats.trader_id <> "_" <> float.to_string(mirror_size)), "mirror/timestamp", fact.Int(activity.timestamp))
    ]
    
    let _ = sharded.transact_shard(state.db, sharded.mirror_shard_id, mirror_facts)
    Nil
}
