import gleam/list
import gleam/result
import gleam/option.{None}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb/shared/types.{type ReactiveDelta, type ReactiveMessage, type QueryResult, Delta, Notify, Subscribe}
import gleamdb/engine
import gleamdb/process_extra as gleamdb_process_extra

type ActiveQuery {
  ActiveQuery(
    query: List(types.BodyClause),
    attributes: List(String),
    subscriber: Subject(ReactiveDelta),
    last_result: QueryResult,
  )
}

type State {
  State(queries: List(ActiveQuery))
}

pub fn start_link() -> Result(Subject(ReactiveMessage), actor.StartError) {
  actor.new(State(queries: []))
  |> actor.on_message(fn(state: State, msg: ReactiveMessage) {
    case msg {
      Subscribe(query, attrs, sub, initial_state) -> {
        let new_query = ActiveQuery(query, attrs, sub, initial_state)
        actor.continue(State(queries: [new_query, ..state.queries]))
      }
      Notify(changed_attrs, db_state) -> {
        let new_queries = list.filter_map(state.queries, fn(aq: ActiveQuery) {
          case gleamdb_process_extra.is_alive(aq.subscriber) {
            False -> Error(Nil)
            True -> {
              let is_affected = list.any(changed_attrs, fn(ca) {
                list.contains(aq.attributes, ca)
              })
              
              case is_affected {
                True -> {
                  let current_result = engine.run(db_state, aq.query, [], None, None)
                  let #(added, removed) = diff(aq.last_result, current_result)
                  
                  case added.rows == [] && removed.rows == [] {
                    True -> Ok(aq)
                    False -> {
                      process.send(aq.subscriber, Delta(added, removed))
                      Ok(ActiveQuery(..aq, last_result: current_result))
                    }
                  }
                }
                False -> Ok(aq)
              }
            }
          }
        })
        actor.continue(State(queries: new_queries))
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

import gleam/set

fn diff(old: QueryResult, new: QueryResult) -> #(QueryResult, QueryResult) {
  let old_set = set.from_list(old.rows)
  let new_set = set.from_list(new.rows)
  
  let added_rows = set.difference(new_set, old_set) |> set.to_list()
  let removed_rows = set.difference(old_set, new_set) |> set.to_list()
  
  #(
    types.QueryResult(rows: added_rows, metadata: new.metadata),
    types.QueryResult(rows: removed_rows, metadata: new.metadata),
  )
}
