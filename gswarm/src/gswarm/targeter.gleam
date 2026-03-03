import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/result
import gswarm/amka_domain.{type TradeActivity}
import gswarm/leaderboard.{type Stats}
import gswarm/types.{type Event, type TargetingPolicy, ScoutSignal}

pub type Message {
  StatsUpdate(Stats)
  SetPolicy(TargetingPolicy)
}

pub type State {
  State(
    policy: TargetingPolicy,
    notifier: fn(Event) -> Nil
  )
}

pub fn start(policy: TargetingPolicy, notifier: fn(Event) -> Nil) -> Result(Subject(Message), actor.StartError) {
  actor.new(State(policy, notifier))
  |> actor.on_message(loop)
  |> actor.start()
  |> result.map(fn(started: actor.Started(Subject(Message))) { started.data })
}

// Phase 20: The Sovereign Targeter
fn loop(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    SetPolicy(new_policy) -> {
      io.println("🎯 [Targeter] Policy updated.")
      actor.continue(State(..state, policy: new_policy))
    }
    StatsUpdate(stats) -> {
      // 1. Whale Detection
      let is_whale = stats.total_invested >. state.policy.min_invested || stats.roi >. state.policy.min_roi
      
      case is_whale {
        True -> {
          state.notifier(ScoutSignal("WhaleSighting", stats.trader_id, stats.roi))
        }
        False -> Nil
      }

      // 2. Target Price Detection
      case list.first(stats.recent_activity) {
        Ok(activity) -> {
          let activity: TradeActivity = activity
          let is_target = activity.price >=. state.policy.target_price_min && activity.price <=. state.policy.target_price_max
          case is_target {
            True -> state.notifier(ScoutSignal("TargetPriceHit", stats.trader_id, activity.price))
            False -> Nil
          }
        }
        Error(_) -> Nil
      }

      actor.continue(state)
    }
  }
}
