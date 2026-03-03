import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/dict.{type Dict}

pub type Message {
  Check(ip: String, reply_to: Subject(Bool))
  Reset
}

pub type State {
  State(
    counts: Dict(String, Int),
    limit: Int
  )
}

pub fn start(limit_per_period: Int) -> Subject(Message) {
  let initial_state = State(dict.new(), limit_per_period)
  let assert Ok(started) = 
    actor.new(initial_state)
    |> actor.on_message(handle_message)
    |> actor.start()
  
  let subj = started.data
  
  // Periodically reset counts (Simple sliding window proxy)
  process.spawn(fn() {
    loop_reset(subj)
  })
  
  subj
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Check(ip, reply_to) -> {
      let current = dict.get(state.counts, ip) |> result_unwrap(0)
      case current < state.limit {
        True -> {
          process.send(reply_to, True)
          actor.continue(State(..state, counts: dict.insert(state.counts, ip, current + 1)))
        }
        False -> {
          process.send(reply_to, False)
          actor.continue(state)
        }
      }
    }
    Reset -> {
      actor.continue(State(..state, counts: dict.new()))
    }
  }
}

fn loop_reset(subj: Subject(Message)) {
  process.sleep(1000) // Reset every 1s
  process.send(subj, Reset)
  loop_reset(subj)
}

fn result_unwrap(res: Result(a, b), default: a) -> a {
  case res {
    Ok(v) -> v
    Error(_) -> default
  }
}
