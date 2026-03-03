import gleam/io
import gleam/float
import gleam/result
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb
import gswarm/strategy.{type Strategy, Buy, Sell}
import gswarm/risk
import gswarm/result_fact
import gswarm/strategy_selector
import gswarm/amka_domain
import gswarm/market
import gswarm/lead_time
import gleamdb/shared/types
import gleamdb/fact
import gswarm/types as event_types
import gleam/list
import gswarm/notifier
import gleam/dict

pub type State {
  State(
    self: Subject(Message),
    db: gleamdb.Db,
    market_id: String,
    balance: Float,
    position: Float,
    peak_balance: Float,
    trades: Int,
    halted: Bool,
    active_strategy: Strategy,
    active_strategy_id: String,
    risk_config: risk.RiskConfig,
    current_price: Float,
    notifier: Subject(notifier.Message)
  )
}

pub type Message {
  TickEvent(price: Float, vector: List(Float))
  InsiderSignal(trader_id: String, score: Float)
  MonitorTrade(trade: amka_domain.TradeActivity)
  SetStrategy(strategy: Strategy, id: String)
  GetStatus(reply_to: Subject(State))
  Shutdown
}

pub fn start_paper_trader(db: gleamdb.Db, market_id: String, initial_balance: Float, notifier_actor: Subject(notifier.Message)) -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    let state = State(
      self: self,
      db: db,
      market_id: market_id,
      balance: initial_balance,
      position: 0.0,
      peak_balance: initial_balance,
      trades: 0,
      halted: False,
      active_strategy: strategy.mean_reversion,
      active_strategy_id: "mean_reversion",
      risk_config: risk.default_config(),
      current_price: 0.0,
      notifier: notifier_actor
    )
    actor.initialised(state) |> actor.returning(self) |> Ok
  })
  |> actor.on_message(loop)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn loop(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Shutdown -> actor.stop()

    TickEvent(price, vector) -> {
      // Check drawdown before any action
      let effective_balance = state.balance +. state.position *. price
      let new_peak = float.max(state.peak_balance, effective_balance)
      let is_halted = risk.check_drawdown(effective_balance, new_peak, state.risk_config)

      case is_halted {
        True -> {
          case state.halted {
            False -> {
              process.send(state.notifier, notifier.Notify(event_types.SystemHealth("PaperTrader", "HALTED — drawdown exceeded " <> float.to_string(state.risk_config.max_drawdown_pct *. 100.0) <> "%")))
              risk.log_risk(effective_balance, new_peak, state.risk_config)
            }
            True -> Nil
          }
           actor.continue(State(..state, halted: True, peak_balance: new_peak, current_price: price))
        }
        False -> {
          // Execute the ACTIVE strategy
          let action = state.active_strategy(vector)
          
          let strat_name = state.active_strategy_id

          let new_state = case action, state.position == 0.0 {
            Buy, True -> {
              // Record Prediction
              // (Prediction is implicit in the Buy action here, but ideally we'd record explicit signal)
              // For Phase 29, let's assume Buy = "up" prediction
              result_fact.record_prediction(state.db, state.market_id, "up", price, strat_name)

              // Risk-gated position sizing
              let pos = risk.size_position(state.balance, price, state.risk_config)
              let cost = pos *. price
              process.send(state.notifier, notifier.Notify(event_types.TradeExecuted("BUY", state.market_id, "Trend", 0.0, state.balance -. cost)))
              State(..state,
                balance: state.balance -. cost,
                position: pos,
                peak_balance: new_peak,
                trades: state.trades + 1,
                halted: False
              )
            }
            Sell, False -> {
               // Record Prediction (Sell = "down")
               result_fact.record_prediction(state.db, state.market_id, "down", price, strat_name)
               
              let proceeds = state.position *. price
              process.send(state.notifier, notifier.Notify(event_types.TradeExecuted("SELL", state.market_id, "Trend", 0.0, state.balance +. proceeds)))
              State(..state,
                balance: state.balance +. proceeds,
                position: 0.0,
                peak_balance: new_peak,
                trades: state.trades + 1,
                halted: False
              )
            }
            _, _ -> State(..state, peak_balance: new_peak, halted: False, current_price: price)
          }
          
          // Adaptive Check: Every 10 trades
          case new_state.trades % 10 == 0 && new_state.trades > 0 {
             True -> {
                 let #(best_id, best_strat) = strategy_selector.best_strategy(state.db)
                 
                 case best_id != state.active_strategy_id {
                   True -> {
                     process.send(state.notifier, notifier.Notify(event_types.SystemHealth("PaperTrader", "Adaptive Swap: " <> best_id)))
                     actor.continue(State(..new_state, active_strategy: best_strat, active_strategy_id: best_id))
                   }
                   False -> actor.continue(new_state)
                 }
             }
             False -> actor.continue(new_state)
          }
        }
      }
    }

     InsiderSignal(trader_id, score) -> {
      // Phase 7: Automated Micro-Execution
      let competence_threshold = state.risk_config.min_signal_score
      
      case score >. competence_threshold && state.balance >. state.risk_config.micro_capital_floor {
        True -> {
          let price = state.current_price
          
          // Simulation: 0.1% Taker Fee, $0.05 Slippage
          let fee_pct = 0.001
          let slippage = 0.05
          let target_roi = 0.05 // We want at least 5% expected move to mirror
          
          let micro_cost = float.min(state.risk_config.micro_trade_limit, state.balance *. state.risk_config.max_position_pct)
          
          case price >. 0.0 && risk.is_roi_positive(micro_cost, fee_pct, slippage, target_roi) {
            True -> {
               process.send(state.notifier, notifier.Notify(event_types.TradeExecuted("MIRROR", state.market_id, trader_id, target_roi, state.balance)))
               
               let pos = micro_cost /. price
               let total_cost = micro_cost +. { micro_cost *. fee_pct } +. slippage
               
               let next_state = State(..state,
                 balance: state.balance -. total_cost,
                 position: state.position +. pos,
                 trades: state.trades + 1
               )
               actor.continue(next_state)
            }
            False -> {
               process.send(state.notifier, notifier.Notify(event_types.TradeGated(state.market_id, "ROI Check FAIL")))
               actor.continue(state)
            }
          }
        }
        _ -> actor.continue(state)
      }
    }

    MonitorTrade(trade) -> {
      // Phase 7: Real-time Mirroring of Verified Insiders
      
      // Use direct deterministic UID lookup (O(1) in GleamDB)
      let tid = fact.phash2(trade.user)
      let query = [
        types.Positive(#(types.Val(fact.Ref(fact.EntityId(tid))), "insider/competence", types.Var("score")))
      ]
      
      let competence = {
        let rows = gleamdb.query(state.db, query).rows
        list.fold(rows, 0.0, fn(acc, row) {
          case dict.get(row, "score") {
            Ok(fact.Float(s)) -> float.max(acc, s)
            _ -> acc
          }
        })
      }
      
      // 2. Perform ROI Gating and First-Mover check
      let others = market.get_trades_in_window(state.db, trade.market_slug, trade.timestamp - 60, trade.timestamp)
      let is_first = lead_time.is_first_mover(trade, others)
      
      case competence >. state.risk_config.min_signal_score && is_first {
        True -> {
           process.send(state.notifier, notifier.Notify(event_types.FirstMover(trade.market_slug, list.length(others) + 1, trade.user)))
           // Reuse the InsiderSignal logic but with immediate execution
           process.send(state.self, InsiderSignal(trade.user, competence))
           actor.continue(state)
        }
        _ -> {
           case is_first {
             False -> process.send(state.notifier, notifier.Notify(event_types.TradeGated(trade.market_slug, "Bot detected (not first mover)")))
             True -> Nil
           }
           actor.continue(state)
        }
      }
    }

    SetStrategy(new_strategy, new_id) -> {
      io.println("🧬 [PaperTrade] Strategy HOT-SWAPPED for " <> state.market_id <> " to " <> new_id)
      actor.continue(State(..state, active_strategy: new_strategy, active_strategy_id: new_id))
    }

    GetStatus(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    
    // Self-message for adaptation (could be triggered externally too)
    // For now, we'll let the supervisor or a tick counter trigger it. 
    // Let's add a periodic check in the tick loop? 
    // No, keep it clean. adaptation logic is external or implicit.
    // Actually, let's trigger it every 100 trades.
  }
}

/// Bridge from live_ticker/market_feed to paper_trader
pub fn broadcast_tick(trader: Subject(Message), price: Float, vector: List(Float)) {
  process.send(trader, TickEvent(price, vector))
}
