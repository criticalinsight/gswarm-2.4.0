import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/list
import gleam/int
import gleam/string
import gleam/io
import gleamdb
import gleamdb/fact.{type Datom}

pub fn start(db: gleamdb.Db) -> Result(Subject(List(Datom)), actor.StartError) {
  let res = actor.new(Nil)
  |> actor.on_message(fn(state, msg: List(Datom)) {
    list.each(msg, fn(d) {
      case d.attribute {
        "alpha/signal" -> {
          let val = case d.value {
            fact.Str(s) -> s
            _ -> string.inspect(d.value)
          }
          io.println("🚀 [TELEMETRY] ALPHA SIGNAL: " <> val)
        }
        "market/latest_vector" -> {
          io.println(
            "📈 [TELEMETRY] MARKET VECTOR UPDATED for entity "
            <> int.to_string(fact.eid_to_integer(d.entity)),
          )
        }
        "trade/insider" -> {
          io.println(
             "🕵️ [TELEMETRY] INSIDER ACTIVITY DETECTED: " <> string.inspect(d.value)
          )
        }
        _ -> Nil
      }
    })
    actor.continue(state)
  })
  |> actor.start()

  case res {
    Ok(started) -> {
      let subj = started.data
      gleamdb.subscribe_wal(db, subj)
      Ok(subj)
    }
    Error(e) -> Error(e)
  }
}
