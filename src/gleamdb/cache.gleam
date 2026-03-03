import gleam/option.{type Option, None, Some}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamdb/fact.{type Datom}
import gleamdb/transactor

pub type Message(k, v) {
  Get(k, Subject(Option(v)))
  Set(k, v)
  Invalidate(k)
  Clear
  HandleWal(List(Datom))
}

pub type CacheConfig(k, v) {
  CacheConfig(max_size: Int, invalidator: fn(Datom, k) -> Bool)
}

type State(k, v) {
  State(entries: Dict(k, v), order: List(k), config: CacheConfig(k, v))
}

/// Start a new LRU cache actor with the given configuration.
pub fn start(
  config: CacheConfig(k, v),
) -> Result(Subject(Message(k, v)), actor.StartError) {
  let res =
    actor.new(State(dict.new(), [], config))
    |> actor.on_message(handle_message)
    |> actor.start()

  case res {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn handle_message(
  state: State(k, v),
  msg: Message(k, v),
) -> actor.Next(State(k, v), Message(k, v)) {
  case msg {
    Get(key, reply_to) -> {
      case dict.get(state.entries, key) {
        Ok(val) -> {
          process.send(reply_to, Some(val))
          actor.continue(state)
        }
        Error(Nil) -> {
          process.send(reply_to, None)
          actor.continue(state)
        }
      }
    }
    Set(key, val) -> {
      let entries = dict.insert(state.entries, key, val)
      let order = [key, ..list.filter(state.order, fn(x) { x != key })]

      // LRU Eviction
      let #(entries, order) = case list.length(order) > state.config.max_size {
        True -> {
          let last = list.last(order) |> result.unwrap(key)
          let order = list.filter(order, fn(x) { x != last })
          let entries = dict.delete(entries, last)
          #(entries, order)
        }
        False -> #(entries, order)
      }

      actor.continue(State(..state, entries: entries, order: order))
    }
    Invalidate(key) -> {
      let entries = dict.delete(state.entries, key)
      let order = list.filter(state.order, fn(x) { x != key })
      actor.continue(State(..state, entries: entries, order: order))
    }
    Clear -> {
      actor.continue(State(dict.new(), [], state.config))
    }
    HandleWal(datoms) -> {
      let invalid_keys =
        list.fold(datoms, [], fn(acc, d) {
          list.fold(dict.keys(state.entries), acc, fn(inner_acc, k) {
            case state.config.invalidator(d, k) {
              True -> [k, ..inner_acc]
              False -> inner_acc
            }
          })
        })
        |> list.unique()

      let entries =
        list.fold(invalid_keys, state.entries, fn(acc, k) { dict.delete(acc, k) })
      let order =
        list.filter(state.order, fn(k) { !list.contains(invalid_keys, k) })
      actor.continue(State(..state, entries: entries, order: order))
    }
  }
}

/// Convenience function to wrap a cache in a simple get/set interface.
pub fn get(cache: Subject(Message(k, v)), key: k) -> Option(v) {
  let reply_to = process.new_subject()
  process.send(cache, Get(key, reply_to))
  case process.receive(reply_to, 5000) {
    Ok(res) -> res
    Error(_) -> None
  }
}

pub fn set(cache: Subject(Message(k, v)), key: k, value: v) -> Nil {
  process.send(cache, Set(key, value))
}

pub fn invalidate(cache: Subject(Message(k, v)), key: k) -> Nil {
  process.send(cache, Invalidate(key))
}

/// Start a reactive cache that automatically invalidates based on database changes.
pub fn start_reactive(
  db: Subject(transactor.Message),
  config: CacheConfig(k, v),
) -> Result(Subject(Message(k, v)), actor.StartError) {
  case start(config) {
    Ok(cache) -> {
      // Create a mapper process that receives List(Datom) and sends HandleWal(datoms) to cache
      process.spawn(fn() {
        let wal_subject = process.new_subject()
        process.send(db, transactor.Subscribe(wal_subject))
        wal_loop(wal_subject, cache)
      })
      Ok(cache)
    }
    Error(e) -> Error(e)
  }
}

fn wal_loop(wal_subject: Subject(List(Datom)), cache: Subject(Message(k, v))) {
  case process.receive(wal_subject, 60_000) {
    Ok(datoms) -> {
      process.send(cache, HandleWal(datoms))
      wal_loop(wal_subject, cache)
    }
    Error(_) -> wal_loop(wal_subject, cache)
  }
}
