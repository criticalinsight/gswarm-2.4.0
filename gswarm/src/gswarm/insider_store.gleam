import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
import gleam/result
import gleam/list
import gleam/int
import gleam/float
import gleamdb
import gleamdb/fact
import gswarm/competence

pub type InsiderStats {
  InsiderStats(
    trader_id: String,
    total_trades: Int,
    successful_insides: Int,
    avg_lead_time: Float,
    confidence_score: Float,
    competence_score: Float,
    lags: List(Float),
    brier_scores: List(Float)
  )
}

pub type Message {
  RecordTrade(
    trader_id: String,
    lag_minutes: Float,
    brier_score: Float
  )
  GetInsiderStats(
    trader_id: String,
    reply_to: Subject(Option(InsiderStats))
  )
  GetAllInsiders(
    reply_to: Subject(List(InsiderStats))
  )
}

pub type State {
  State(
    db: gleamdb.Db,
    insiders: Dict(String, InsiderStats)
  )
}

pub fn start(db: gleamdb.Db) -> Result(Subject(Message), actor.StartError) {
  configure_schema(db)
  actor.new(State(db, dict.new()))
  |> actor.on_message(loop)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

pub fn configure_schema(db: gleamdb.Db) {
  let config = fact.AttributeConfig(unique: False, component: False, retention: fact.LatestOnly, cardinality: fact.One, check: None)
  let unique_config = fact.AttributeConfig(unique: True, component: False, retention: fact.LatestOnly, cardinality: fact.One, check: None)
  
  let _ = gleamdb.set_schema(db, "insider/id", unique_config)
  let _ = gleamdb.set_schema(db, "insider/competence", config)
  let _ = gleamdb.set_schema(db, "insider/confidence", config)
  let _ = gleamdb.set_schema(db, "insider/avg_lag", config)
  Nil
}

fn loop(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    RecordTrade(trader_id, lag, brier) -> {
      let stats = dict.get(state.insiders, trader_id) |> result.unwrap(
        InsiderStats(trader_id, 0, 0, 0.0, 0.0, 0.0, [], [])
      )
      
      let new_lags = list.take([lag, ..stats.lags], 20)
      let new_briers = list.take([brier, ..stats.brier_scores], 20)
      let new_total = stats.total_trades + 1
      let is_success = lag <. -0.1 // Trade happened >6 seconds before move (Phase 7 adjust)
      let new_success = case is_success {
        True -> stats.successful_insides + 1
        False -> stats.successful_insides
      }
      
      // Compute new average lead time
      let new_avg = list.fold(new_lags, 0.0, fn(acc, l) { acc +. l }) /. int.to_float(list.length(new_lags))
      
      // Compute new average brier
      let avg_brier = list.fold(new_briers, 0.0, fn(acc, b) { acc +. b }) /. int.to_float(list.length(new_briers))
      
      // Compute confidence
      let success_rate = int.to_float(new_success) /. int.to_float(new_total)
      let weight = float.logarithm(int.to_float(new_total) +. 1.0) |> result.unwrap(0.0)
      let new_confidence = float.min(1.0, success_rate *. { weight /. 2.0 })
      
      // Compute competence (Phase 6)
      // We use confidence as the "alpha" base for now
      let new_competence = competence.calculate_competence_index(new_confidence, avg_brier, new_total)
      
      let new_stats = InsiderStats(
        trader_id,
        new_total,
        new_success,
        new_avg,
        new_confidence,
        new_competence,
        new_lags,
        new_briers
      )
      
      // Persist to GleamDB
      let tid = fact.deterministic_uid(trader_id)
      let _ = gleamdb.transact(state.db, [
        #(tid, "insider/id", fact.Str(trader_id)),
        #(tid, "insider/confidence", fact.Float(new_confidence)),
        #(tid, "insider/competence", fact.Float(new_competence)),
        #(tid, "insider/avg_lag", fact.Float(new_avg))
      ])
      
      let new_insiders = dict.insert(state.insiders, trader_id, new_stats)
      actor.continue(State(state.db, new_insiders))
    }
    
    GetInsiderStats(tid, reply_to) -> {
      process.send(reply_to, dict.get(state.insiders, tid) |> option.from_result)
      actor.continue(state)
    }
    
    GetAllInsiders(reply_to) -> {
      process.send(reply_to, dict.values(state.insiders))
      actor.continue(state)
    }
  }
}
