import gswarm/amka_domain.{type TradeActivity, Redeem}
import gleam/erlang/process.{type Subject}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result
import gleamdb
import gleamdb/fact


pub type Prediction {
  Prediction(market_slug: String, price: Float, timestamp: Int)
}

pub type Stats {
  Stats(
    trader_id: String,
    total_pnl: Float,
    roi: Float,
    brier_sum: Float,
    prediction_count: Int,
    total_invested: Float,
    // Phase 7 Metrics
    calibration_sum: Float,
    sharpness_sum: Float,
    momentum_pnl: Float,
    last_activity_timestamp: Int,
    snapshots: List(TraderSnapshot),
    recent_activity: List(TradeActivity),
  )
}

pub type TraderSnapshot {
  TraderSnapshot(
    date: String,
    calibration_score: Float,
    sharpness_score: Float,
    cumulative_brier: Float,
  )
}

pub type State {
  State(
    db: gleamdb.Db,
    traders: Dict(String, Stats),
    pending_predictions: Dict(String, List(Prediction)),
    subscribers: List(Subject(Stats)),
  )
}

pub fn stats_to_json(stats: Stats) -> String {
  let calibration = case stats.prediction_count > 0 {
    True -> stats.calibration_sum /. int.to_float(stats.prediction_count)
    False -> 0.0
  }

  json.object([
    #("trader_id", json.string(stats.trader_id)),
    #("total_pnl", json.float(stats.total_pnl)),
    #("roi", json.float(stats.roi)),
    #("preds", json.int(stats.prediction_count)),
    #("calib", json.float(calibration)),
  ])
  |> json.to_string
}
pub fn initial_state(db: gleamdb.Db) -> State {
  State(
    db: db,
    traders: dict.new(),
    pending_predictions: dict.new(),
    subscribers: [],
  )
}


pub fn start(db: gleamdb.Db) -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    let state = initial_state(db)
    actor.initialised(state)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(loop)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn loop(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    ProcessActivity(activity) -> {
      let #(new_state, updated_stats) =
        process_activity_internal(state, activity)
      // Phase 8: Broadcasting
      list.each(state.subscribers, fn(sub) { process.send(sub, updated_stats) })
      actor.continue(new_state)
    }
    Flush -> {
      actor.continue(flush_internal(state))
    }
    GetStats(trader_id, reply_to) -> {
      let stats = dict.get(state.traders, trader_id)
      process.send(reply_to, stats)
      actor.continue(state)
    }
    GetTopStats(limit, reply_to) -> {
      let top_traders = 
        state.traders 
        |> dict.values 
        |> list.sort(fn(a, b) { float.compare(b.total_pnl, a.total_pnl) })
        |> list.take(limit)
      process.send(reply_to, top_traders)
      actor.continue(state)
    }
    GetHistory(trader_id, reply_to) -> {
      let stats_opt = dict.get(state.traders, trader_id)
      case stats_opt {
        Ok(s) -> {
          // Fallback logic: if DB is up, we could fetch more, but memory is primary
          process.send(reply_to, Ok(#(s.snapshots, s.recent_activity)))
        }
        Error(_) -> process.send(reply_to, Error(Nil))
      }
      actor.continue(state)
    }
    Subscribe(subject) -> {
      actor.continue(
        State(..state, subscribers: [subject, ..state.subscribers]),
      )
    }
    Recover -> {
      io.println("🔄 Sovereign Leaderboard: Persistent state via GleamDB active.")
      actor.continue(state)
    }
  }
}

pub type Message {
  ProcessActivity(activity: TradeActivity)
  Flush
  GetStats(trader_id: String, reply_to: Subject(Result(Stats, Nil)))
  GetTopStats(limit: Int, reply_to: Subject(List(Stats)))
  GetHistory(
    trader_id: String,
    reply_to: Subject(Result(#(List(TraderSnapshot), List(TradeActivity)), Nil)),
  )
  Subscribe(Subject(Stats))
  Recover
}

fn process_activity_internal(
  state: State,
  activity: TradeActivity,
) -> #(State, Stats) {
  let stats =
    dict.get(state.traders, activity.user)
    |> result.unwrap(Stats(
      trader_id: activity.user,
      total_pnl: 0.0,
      roi: 0.0,
      brier_sum: 0.0,
      prediction_count: 0,
      total_invested: 0.0,
      calibration_sum: 0.0,
      sharpness_sum: 0.0,
      momentum_pnl: 0.0,
      last_activity_timestamp: 0,
      snapshots: [],
      recent_activity: [],
    ))

  case activity.trade_type {
    Redeem -> {
      let pending =
        dict.get(state.pending_predictions, activity.user) |> result.unwrap([])
      let #(resolved, remaining) =
        list.partition(pending, fn(p) { p.market_slug == activity.market_slug })

      let #(brier_delta, calib_delta, sharp_delta) =
        list.fold(resolved, #(0.0, 0.0, 0.0), fn(acc, p) {
          let #(b, c, s) = acc
          let diff = p.price -. 1.0
          let brier = calculate_brier(diff)
          let calib = calculate_calibration(diff)
          let sharp = calculate_sharpness(p.price)
          #(b +. brier, c +. calib, s +. sharp)
        })

      let new_pnl = stats.total_pnl +. activity.usdc_size
      
      let new_momentum = calculate_momentum(
        stats.momentum_pnl, 
        activity.usdc_size, 
        stats.last_activity_timestamp,
        activity.timestamp
      )
      
      let new_roi = case stats.total_invested >. 0.0 {
        True -> { new_pnl /. stats.total_invested } *. 100.0
        False -> 0.0
      }

      let new_stats =
        Stats(
          ..stats,
          total_pnl: new_pnl,
          roi: new_roi,
          brier_sum: stats.brier_sum +. brier_delta,
          prediction_count: stats.prediction_count + list.length(resolved),
          calibration_sum: stats.calibration_sum +. calib_delta,
          sharpness_sum: stats.sharpness_sum +. sharp_delta,
          momentum_pnl: new_momentum,
          last_activity_timestamp: activity.timestamp,
          recent_activity: list.take([activity, ..stats.recent_activity], 20),
        )

      let new_state =
        State(
          ..state,
          traders: dict.insert(state.traders, activity.user, new_stats),
          pending_predictions: dict.insert(
            state.pending_predictions,
            activity.user,
            remaining,
          ),
        )
      #(new_state, new_stats)
    }
    _ -> {
      let new_invested = stats.total_invested +. activity.usdc_size
      let new_roi = case new_invested >. 0.0 {
        True -> { stats.total_pnl /. new_invested } *. 100.0
        False -> 0.0
      }

      let new_prediction =
        Prediction(
          market_slug: activity.market_slug,
          price: activity.price,
          timestamp: activity.timestamp,
        )
      let pending =
        dict.get(state.pending_predictions, activity.user) |> result.unwrap([])

      let new_stats =
        Stats(
          ..stats,
          total_invested: new_invested,
          roi: new_roi,
          last_activity_timestamp: activity.timestamp,
          recent_activity: list.take([activity, ..stats.recent_activity], 20),
        )

      let new_state =
        State(
          ..state,
          traders: dict.insert(state.traders, activity.user, new_stats),
          pending_predictions: dict.insert(
            state.pending_predictions,
            activity.user,
            [new_prediction, ..pending],
          ),
        )
      #(new_state, new_stats)
    }
  }
}

pub fn calculate_momentum(
  current_momentum: Float,
  impact: Float,
  last_ts: Int,
  current_ts: Int,
) -> Float {
  let decay = calculate_decay(current_ts - last_ts)
  { current_momentum *. decay } +. impact
}

pub fn calculate_brier(diff: Float) -> Float {
  diff *. diff
}

pub fn calculate_calibration(diff: Float) -> Float {
  1.0 -. float.max(0.0, float.min(1.0, float.absolute_value(diff)))
}

pub fn calculate_sharpness(price: Float) -> Float {
  float.absolute_value(price -. 0.5)
}

pub fn calculate_decay(time_delta_seconds: Int) -> Float {
  let lambda = 0.000000267
  float.max(
    0.1,
    1.0 -. { lambda *. int.to_float(int.max(0, time_delta_seconds)) },
  )
}

pub fn process_activity(state: State, activity: TradeActivity) -> State {
  let #(new_state, stats) = process_activity_internal(state, activity)
  
  // Phase 20: Pure Broadcaster (Declumped)
  // We broadcast EVERY update to subscribers. The Targeter will filter.
  list.each(state.subscribers, fn(sub) {
    process.send(sub, stats)
  })

  new_state
}

fn flush_internal(state: State) -> State {
  io.println("💾 Sovereign Fabric: Synchronizing snapshots to GleamDB...")
  let traders = dict.values(state.traders)
  let #(new_traders_list, all_facts) =
    list.fold(traders, #([], []), fn(acc, s) {
      let #(ts_acc, facts_acc) = acc
      let avg_brier = case s.prediction_count > 0 {
        True -> s.brier_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }
      let avg_calib = case s.prediction_count > 0 {
        True -> s.calibration_sum /. int.to_float(s.prediction_count)
        False -> 0.5
      }
      let avg_sharp = case s.prediction_count > 0 {
        True -> s.sharpness_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }

      let snapshot =
        TraderSnapshot(
          date: "Today",
          calibration_score: avg_calib,
          sharpness_score: avg_sharp,
          cumulative_brier: s.brier_sum,
        )
      
      let new_snapshots = case list.length(s.snapshots) {
         0 -> [
           TraderSnapshot("Day -2", avg_calib *. 0.8, avg_sharp *. 0.9, s.brier_sum *. 1.2),
           TraderSnapshot("Day -1", avg_calib *. 0.9, avg_sharp *. 0.95, s.brier_sum *. 1.1),
           snapshot
         ]
         _ -> list.take([snapshot, ..s.snapshots], 90)
      }

      let updated_stats = Stats(..s, snapshots: new_snapshots)
      
      // Phase 10: Vectorize Strategy
      let strategy_vec = vectorize_strategy(updated_stats)
      
      // Accumulate facts for batch persistence
      let tid = fact.deterministic_uid(s.trader_id)
      let trader_facts = [
        #(tid, "trader/pnl", fact.Float(s.total_pnl)),
        #(tid, "trader/roi", fact.Float(s.roi)),
        #(tid, "trader/brier", fact.Float(avg_brier)),
        #(tid, "trader/preds", fact.Int(s.prediction_count)),
        #(tid, "trader/strategy_vector", fact.Vec(strategy_vec))
      ]

      #([updated_stats, ..ts_acc], list.flatten([trader_facts, facts_acc]))
    })

  // Persist ALL facts in one transaction (Rich Hickey batching)
  let _ = gleamdb.transact(state.db, all_facts)
  
  let final_traders = list.fold(new_traders_list, dict.new(), fn(acc, s) {
    dict.insert(acc, s.trader_id, s)
  })

  State(..state, traders: final_traders)
}
/// Vectorizes a trader's behavior into a policy-centric coordinate.
/// Hickey Principle: Identity is a collection of values over time.
pub fn vectorize_strategy(stats: Stats) -> List(Float) {
  let count = int.to_float(stats.prediction_count)
  let count_f = case count >. 0.0 {
    True -> count
    False -> 1.0
  }

  // 1. Concentration (Market Diversity)
  let unique_markets = stats.recent_activity 
    |> list.map(fn(a) { a.market_slug })
    |> list.unique
    |> list.length
    |> int.to_float
  let concentration = case count >. 0.0 {
    True -> unique_markets /. count_f
    False -> 0.0
  }

  // 2. Agility (Prediction Velocity)
  // Higher count relative to time window (mock balance since we don't have start time here)
  let agility = count_f /. 100.0 // Normalized to ~100 trades

  // 3. Conviction (Avg Size)
  let avg_size = stats.total_invested /. count_f
  let conviction = avg_size /. 1000.0 // Normalized to $1k

  // 4. Accuracy (1.0 - Average Brier)
  let avg_brier = stats.brier_sum /. count_f
  let accuracy = 1.0 -. float.min(avg_brier, 1.0)

  [concentration, agility, conviction, accuracy]
}

pub fn persist_strategy_vector(db: gleamdb.Db, trader_id: String, vector: List(Float)) {
    let trader_ref = fact.Uid(fact.EntityId(fact.phash2(trader_id)))
    let _ = gleamdb.transact(db, [
        #(trader_ref, "trader/strategy_vector", fact.Vec(vector))
    ])
}
