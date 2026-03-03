import gleam/io
import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/int
import gleam/list
import gleam/string
import gswarm/telegram
import gswarm/leaderboard

import gswarm/types.{type Event, ScoutSignal}

import gleamdb

import gleam/float

pub type Message {
  Notify(Event)
  HandleUpdate(telegram.Update)
  RegisterStatusHandler(fn() -> String)
  RegisterLeaderboard(process.Subject(leaderboard.Message))
  RegisterDb(gleamdb.Db)
}

pub type State {
  State(
    token: String, 
    chat_id: String, 
    last_update_id: Int,
    status_handler: Option(fn() -> String),
    leaderboard: Option(process.Subject(leaderboard.Message)),
    db: Option(gleamdb.Db),
    threshold: Float
  )
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  io.println("🤖 [Notifier] Starting Telegram Notifier actor...")
  let token = telegram.get_token() |> result.unwrap("")
  let chat_id = telegram.get_chat_id() |> result.unwrap("")
  
  case token != "" && chat_id != "" {
    True -> io.println("🤖 [Notifier] Credentials loaded (Token: " <> string.slice(token, 0, 5) <> "..., ChatID: " <> chat_id <> ")")
    False -> io.println("🤖 [Notifier] WARNING: Missing Telegram credentials!")
  }
  
  actor.new_with_initialiser(1000, fn(self) {
    let state = State(token, chat_id, 0, None, None, None, 0.7)
    
    // Spawn listener process
    process.spawn(fn() {
      listener_loop(self, token, 0)
    })
    
    actor.initialised(state) |> actor.returning(self) |> Ok
  })
  |> actor.on_message(loop)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

import gswarm/reporter

fn loop(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    RegisterDb(db) -> {
      actor.continue(State(..state, db: Some(db)))
    }
    Notify(event) -> {
      case event {
        ScoutSignal(_, trader_id, _) -> {
          case state.leaderboard, state.db {
            Some(lb), Some(db) -> {
              let reply_subject = process.new_subject()
              process.send(lb, leaderboard.GetStats(trader_id, reply_subject))
              case process.receive(reply_subject, 5000) {
                Ok(Ok(stats)) -> {
                  case stats.roi >=. 50.0 {
                    True -> {
                      let report = reporter.generate_trader_report(db, stats)
                      send_telegram(state, report)
                    }
                    False -> io.println("🔇 [Notifier] Signal Silence: " <> stats.trader_id <> " (" <> float.to_string(stats.roi) <> "%) < 50%")
                  }
                }
                _ -> io.println("❌ [Notifier] Stats missing for " <> trader_id)
              }
            }
            _, _ -> io.println("❌ [Notifier] ScoutSignal: DB/LB missing.")
          }
        }
        _ -> Nil // Ignore non-intelligence signals
      }
      actor.continue(state)
    }
    RegisterStatusHandler(handler) -> {
      actor.continue(State(..state, status_handler: Some(handler)))
    }
    RegisterLeaderboard(lb) -> {
      actor.continue(State(..state, leaderboard: Some(lb)))
    }
    HandleUpdate(update) -> {
      let state = State(..state, last_update_id: update.id + 1)
      case update.message {
        "/status" -> {
          handle_status(state)
          actor.continue(state)
        }
        "/report " <> trader_id -> {
          case state.leaderboard, state.db {
            Some(lb), Some(db) -> {
              let reply_subject = process.new_subject()
              process.send(lb, leaderboard.GetStats(trader_id, reply_subject))
              case process.receive(reply_subject, 5000) {
                Ok(Ok(stats)) -> {
                  case stats.roi >=. 50.0 {
                    True -> {
                      let report = reporter.generate_trader_report(db, stats)
                      send_telegram(state, report)
                    }
                    False -> send_telegram(state, "❌ ROI " <> float.to_string(stats.roi) <> "% is below 50% threshold.")
                  }
                }
                _ -> send_telegram(state, "❌ Could not find stats for " <> trader_id)
              }
            }
            _, _ -> send_telegram(state, "❌ Leaderboard or DB not initialized.")
          }
          actor.continue(state)
        }
        _ -> actor.continue(state)
      }
    }
  }
}

fn listener_loop(parent: Subject(Message), token: String, offset: Int) {
  case telegram.get_updates(token, offset) {
    Ok(updates) -> {
      case list.length(updates) {
        0 -> Nil
        n -> {
          io.println("🤖 [Notifier] Received " <> int.to_string(n) <> " Telegram updates")
          list.each(updates, fn(u: telegram.Update) {
            process.send(parent, HandleUpdate(u))
          })
        }
      }
      let new_offset = case list.last(updates) {
        Ok(u) -> u.id + 1
        Error(_) -> offset
      }
      process.sleep(3000)
      listener_loop(parent, token, new_offset)
    }
    Error(e) -> {
      io.println("⚠️ [Notifier] Update Error: " <> e)
      process.sleep(10000)
      listener_loop(parent, token, offset)
    }
  }
}

fn send_telegram(state: State, text: String) {
  case state.token != "" && state.chat_id != "" {
    True -> {
      process.spawn(fn() {
        case telegram.send_message(state.token, state.chat_id, text) {
          Ok(_) -> io.println("🤖 [Notifier] Telegram message sent.")
          Error(e) -> io.println("❌ [Notifier] Telegram Error: " <> e)
        }
      })
      Nil
    }
    False -> {
      io.println("📢 [Notifier] (Dry Run):")
      io.println(text)
    }
  }
}

fn handle_status(state: State) {
  let header = "🐝 *Gswarm Status Report*\n"
  let body = case state.status_handler {
    Some(h) -> h()
    None -> "⚠️ No status handler registered"
  }
  send_telegram(state, header <> body)
}
