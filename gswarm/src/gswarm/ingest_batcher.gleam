import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/int
import gleam/result
import gleam/io
import gleamdb
import gswarm/market.{type PredictionTick}
import gswarm/registry_actor
import gswarm/lead_time
import gswarm/insider_store
import gswarm/competence
import gswarm/amka_domain
import gswarm/paper_trader
import gleam/option.{None, Some}
import gleam/float
import gleam/dict.{type Dict}

pub type Message {
  Ingest(tick: PredictionTick, vector: List(Float))
  RegisterTrader(market_id: String, subject: Subject(paper_trader.Message))
  MonitorTrade(trade: amka_domain.TradeActivity)
  Flush
}

pub type BatcherState {
  BatcherState(
    db: gleamdb.Db,
    registry_actor: Subject(registry_actor.Message),
    buffer: List(#(PredictionTick, List(Float))),
    last_flush: Int,
    batch_size_limit: Int,
    flush_interval_ms: Int,
    insider_store: Subject(insider_store.Message),
    traders: Dict(String, Subject(paper_trader.Message))
  )
}

pub fn start(
  db: gleamdb.Db, 
  registry_actor: Subject(registry_actor.Message),
  insider_store: Subject(insider_store.Message)
) -> Result(Subject(Message), actor.StartError) {
  let initial_state = BatcherState(
    db: db,
    registry_actor: registry_actor,
    buffer: [],
    last_flush: 0,
    batch_size_limit: 10,
    flush_interval_ms: 1000,
    insider_store: insider_store,
    traders: dict.new()
  )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle_message(state: BatcherState, msg: Message) -> actor.Next(BatcherState, Message) {
  case msg {
    Ingest(tick, vector) -> {
      let new_buffer = [#(tick, vector), ..state.buffer]
      process.send(state.registry_actor, registry_actor.RecordMarket(tick.market_id))
      
      let next_state = BatcherState(..state, buffer: new_buffer)
      case list.length(new_buffer) >= state.batch_size_limit {
        True -> {
          do_flush(next_state)
          actor.continue(BatcherState(..next_state, buffer: [], last_flush: erlang_system_time()))
        }
        False -> actor.continue(next_state)
      }
    }

    MonitorTrade(trade) -> {
      let db = state.db
      let store = state.insider_store
      let traders = state.traders
      
      // 1. Record trade activity for "First-Mover" analysis
      let _ = market.record_trade_activity(db, trade)
      
      // 2. Notify PaperTrader IMMEDIATELY for Micro-Copytrading (Phase 7)
      case dict.get(traders, trade.market_slug) {
        Ok(trader) -> {
          // Attempt to get the trader's competence from store? 
          // For now, let the paper_trader determine competence since it's the actor's job to gate.
          // Wait, incompetence/competence is stored in InsiderStore.
          // Let's modify the message to include a request for competence?
          // Actually, InsiderStore can broadcast updates, but for now, 
          // the paper_trader can just store its own view of insiders or query.
          // Let's send a specific MonitorTrade message to the paper_trader.
          process.send(trader, paper_trader.MonitorTrade(trade))
        }
        _ -> Nil
      }

      process.spawn_unlinked(fn() {
         process.sleep(5000) // 5s for demo/sim
         
         case market.get_probability_series_since(db, trade.market_slug, "Yes", trade.timestamp) {
           Ok(series) -> {
             let ticks = list.map(series, fn(pair) {
               let #(ts, p) = pair
               market.PredictionTick(trade.market_slug, "Yes", p, 0, ts, "manifold_history")
             })
             
             let leg_ticks = list.map(ticks, fn(pt) {
                market.Tick(pt.market_id, pt.outcome, pt.probability, pt.volume, pt.timestamp, pt.trader_id)
             })

             case lead_time.compute_lag(trade, leg_ticks) {
                Some(lag) -> {
                  io.println("🕵️‍♂️ Insider Signal: Lag " <> float.to_string(lag.minutes) <> "m")
                  
                  let final_p = case list.last(series) {
                    Ok(#(_, p)) -> p
                    _ -> trade.price
                  }
                  let brier = competence.calculate_brier_score(trade.price, final_p)
                  
                  process.send(store, insider_store.RecordTrade(trade.user, lag.minutes, brier))
                  
                  let score = 1.0 -. brier
                  case dict.get(traders, trade.market_slug) {
                    Ok(trader) -> process.send(trader, paper_trader.InsiderSignal(trade.user, score))
                    _ -> Nil
                  }
                }
                None -> Nil
             }
           }
           Error(_) -> Nil
         }
      })
      actor.continue(state)
    }

    Flush -> {
      do_flush(state)
      actor.continue(BatcherState(..state, buffer: [], last_flush: erlang_system_time()))
    }

    RegisterTrader(mid, subject) -> {
      let new_traders = dict.insert(state.traders, mid, subject)
      actor.continue(BatcherState(..state, traders: new_traders))
    }
  }
}

fn do_flush(state: BatcherState) -> Nil {
  case state.buffer {
    [] -> Nil
    ticks -> {
      io.println("🚀 Batching Ingest: " <> int.to_string(list.length(ticks)) <> " ticks")
      let _ = market.ingest_batch_with_vectors(state.db, list.reverse(ticks))
      Nil
    }
  }
}

fn erlang_system_time() -> Int {
  do_system_time(1000)
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int
