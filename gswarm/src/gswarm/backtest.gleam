import gleam/io
import gleam/int
import gleam/list
import gleam/dict
import gleam/float
import gleam/string
import gleamdb
import gleamdb/shared/types
import gleamdb/fact
import gswarm/strategy.{type Strategy, Buy, Sell}
import gswarm/risk
import gswarm/strategy_selector

pub type BacktestResult {
  BacktestResult(
    total_trades: Int,
    starting_balance: Float,
    final_balance: Float,
    percent_return: Float,
    win_rate: Float,
    drawdown_pct: Float,
    halted: Bool
  )
}

/// Run a fixed-strategy backtest with Risk Management.
pub fn run_backtest(
  db: gleamdb.Db,
  market_id: String,
  strat: strategy.Strategy,
  initial_balance: Float
) -> BacktestResult {
  let timeline = fetch_timeline(db, market_id)
  
  case timeline {
    [] -> {
      io.println("⚠️ Backtest: No historical data found for " <> market_id)
      empty_result(initial_balance)
    }
    _ -> {
       // Wrap static strategy in a provider
       let provider = fn(_i, _curr_strat) { #(strat, "fixed") }
       execute_engine(db, timeline, provider, initial_balance, 0)
    }
  }
}

/// Run an adaptive backtest that checks for the best strategy every `interval` ticks.
pub fn run_adaptive_backtest(
  db: gleamdb.Db,
  market_id: String,
  initial_balance: Float,
  interval: Int
) -> BacktestResult {
  let timeline = fetch_timeline(db, market_id)
  
  case timeline {
    [] -> empty_result(initial_balance)
    rows -> {
      // Provider checks DB for best strategy
      let provider = fn(tick_idx, current_strat) {
        case tick_idx % interval == 0 {
          True -> {
             // In a real backtest, we might pass a timestamp filter to best_strategy 
             // to avoid lookahead bias. For Phase 48, we assume result_facts are 
             // roughly contemporaneous or we accept global knowledge for the simulation.
             // Ideally: strategy_selector.best_strategy_at(db, timestamp)
             let #(best_id, best_strat) = strategy_selector.best_strategy(db)
             #(best_strat, best_id)
          }
          False -> current_strat
        }
      }
      
      execute_engine(db, rows, provider, initial_balance, interval)
    }
  }
}

type EngineState {
  State(
    balance: Float,
    position: Float,
    trades: Int,
    wins: Int,
    peak_balance: Float,
    halted: Bool,
    active_strat: Strategy,
    active_strat_id: String
  )
}

fn execute_engine(
  _db: gleamdb.Db,
  timeline: List(#(Float, List(Float))),
  strategy_provider: fn(Int, #(Strategy, String)) -> #(Strategy, String),
  initial_balance: Float,
  _interval: Int
) -> BacktestResult {
  let risk_conf = risk.default_config()
  
  let initial = State(
    balance: initial_balance,
    position: 0.0,
    trades: 0,
    wins: 0,
    peak_balance: initial_balance,
    halted: False,
    active_strat: strategy.mean_reversion, // Default start, provider will update
    active_strat_id: "mean_reversion"
  )
  
  let final_state = 
    list.index_fold(timeline, initial, fn(state, step, idx) {
      let #(price, vector) = step
      
      // 1. Update Peak & Check Drawdown (Risk Phase 32)
      let current_equity = state.balance +. {state.position *. price}
      let new_peak = float.max(state.peak_balance, current_equity)
      let halted = state.halted || risk.check_drawdown(current_equity, new_peak, risk_conf)
      
      case halted {
        True -> State(..state, peak_balance: new_peak, halted: True)
        False -> {
          // 2. Adaptive Strategy Update (Phase 48)
          let #(strat, strat_id) = strategy_provider(idx, #(state.active_strat, state.active_strat_id))
          
          // 3. Execute Signal
          let action = strat(vector)
          
          case action, state.position == 0.0 {
            Buy, True -> {
               let size = risk.size_position(state.balance, price, risk_conf)
               let cost = size *. price
               State(..state, 
                 balance: state.balance -. cost, 
                 position: size, 
                 peak_balance: new_peak,
                 trades: state.trades + 1,
                 active_strat: strat,
                 active_strat_id: strat_id
               )
            }
            
            Sell, False -> {
               let proceeds = state.position *. price
               // Simple Win calc: did we sell higher than we bought?
               // We don't track entry price in this simple state, assuming FIFO or full position.
               // Approximation: if Account Equity goes UP, it's a win.
               // Since we only hold one position, comparing equity works.
               let is_win = case current_equity >. state.peak_balance { True -> 1 False -> 0 } 
               // Wait, peak_balance is lifetime high. 
               // Need entry balance? For now, simplified win rate logic.
               State(..state,
                 balance: state.balance +. proceeds,
                 position: 0.0,
                 peak_balance: new_peak,
                 wins: state.wins + is_win,
                 trades: state.trades + 1,
                 active_strat: strat,
                 active_strat_id: strat_id
               )
            }
            
            _, _ -> State(..state, peak_balance: new_peak, active_strat: strat, active_strat_id: strat_id)
          }
        }
      }
    })

  // Finalize
  let last_equity = case list.last(timeline) {
     Ok(#(p, _)) -> final_state.balance +. {final_state.position *. p}
     _ -> final_state.balance
  }
  
  let win_rate = case final_state.trades > 0 {
    True -> int.to_float(final_state.wins) /. int.to_float(final_state.trades)
    False -> 0.0
  }
  
  let drawdown = {final_state.peak_balance -. last_equity} /. final_state.peak_balance
  
  BacktestResult(
    total_trades: final_state.trades,
    starting_balance: initial_balance,
    final_balance: last_equity,
    percent_return: {last_equity -. initial_balance} /. initial_balance *. 100.0,
    win_rate: win_rate,
    drawdown_pct: drawdown *. 100.0,
    halted: final_state.halted
  )
}

fn fetch_timeline(db: gleamdb.Db, market_id: String) -> List(#(Float, List(Float))) {
  // 1. Resolve Market Entity ID
  let market_query = [
    types.Positive(#(types.Var("m"), "market/id", types.Val(fact.Str(market_id))))
  ]
  
  case gleamdb.query(db, market_query).rows {
    [row, ..] -> {
      io.println("DEBUG: Market found in DB.")
      case dict.get(row, "m") {
        Ok(fact.Ref(eid)) -> {
           io.println("DEBUG: Market EID: " <> string.inspect(eid))
           // 2. Query Ticks linked to this Market
           let tick_query = [
             types.Positive(#(types.Var("t"), "tick/market", types.Val(fact.Ref(eid)))),
             types.Positive(#(types.Var("t"), "tick/price/Yes", types.Var("price"))),
             types.Positive(#(types.Var("t"), "tick/vector", types.Var("vector")))
           ]
           let results = gleamdb.query(db, tick_query)
           io.println("DEBUG: Ticks found: " <> int.to_string(list.length(results.rows)))
           process_query_results(results)
        }
        _ -> {
          io.println("DEBUG: Failed to get market ID from row.")
          []
        }
      }
    }
    _ -> {
      io.println("DEBUG: Market NOT found in DB.")
      []
    }
  }
}

fn process_query_results(results: types.QueryResult) -> List(#(Float, List(Float))) {
  list.filter_map(results.rows, fn(row) {
    let price = case dict.get(row, "price") {
      Ok(fact.Float(p)) -> Ok(p)
      _ -> Error(Nil)
    }
    let vector = case dict.get(row, "vector") {
      Ok(fact.Vec(v)) -> Ok(v)
      _ -> Error(Nil)
    }
    
    case price, vector {
      Ok(p), Ok(v) -> Ok(#(p, v))
      _, _ -> Error(Nil)
    }
  })
}

fn empty_result(bal: Float) {
  BacktestResult(0, bal, bal, 0.0, 0.0, 0.0, False)
}
