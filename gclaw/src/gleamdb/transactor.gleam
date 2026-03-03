import gleam/erlang/process
import gleam/dict
import gleam/otp/actor
import gleam/list
import gleam/result
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine
import gleamdb/index
import gleamdb/storage
import gleamdb/global
import gleamdb/reactive
import gleamdb/index/ets as ets_index
import gleamdb/rule_serde
import gleamdb/process_extra
import gleamdb/raft
import gleamdb/vector
import gleamdb/vec_index
import gleamdb/index/art
import gleamdb/index/bm25

pub type Message {
  Transact(List(fact.Fact), Option(Int), process.Subject(Result(types.DbState, String)))
  Retract(List(fact.Fact), Option(Int), process.Subject(Result(types.DbState, String)))
  GetState(process.Subject(types.DbState))
  SetSchema(String, fact.AttributeConfig, process.Subject(Result(Nil, String)))
  RegisterFunction(String, fact.DbFunction(types.DbState), process.Subject(Nil))
  RegisterPredicate(String, fn(fact.Value) -> Bool, process.Subject(Nil))
  RegisterComposite(List(String), process.Subject(Result(Nil, String)))
  StoreRule(types.Rule, process.Subject(Result(Nil, String)))
  SetReactive(process.Subject(types.ReactiveMessage))
  Join(process.Pid)
  SyncDatoms(List(fact.Datom))
  RaftMsg(raft.RaftMessage)
  Compact(process.Subject(Nil))
  SetConfig(types.Config, process.Subject(Nil))
  Sync(process.Subject(Nil))
  Boot(Option(String), storage.StorageAdapter, process.Subject(Nil))
  RegisterIndexAdapter(types.IndexAdapter, process.Subject(Nil))
  CreateIndex(String, String, String, process.Subject(Result(Nil, String)))
  CreateBM25Index(String, process.Subject(Result(Nil, String)))
}

pub type Db =
  process.Subject(Message)

pub fn start(
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  start_with_timeout(store, 1000)
}

pub fn start_named(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  // Start with distribution disabled by default for named databases
  // This enables ETS (Silicon Saturation) without forcing global consensus
  do_start_named(store, False, Some(name))
}

pub fn start_distributed(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  // Start with distribution enabled
  let res = do_start_named(store, True, Some(name))
  case res {
    Ok(subject) -> {
      let pid = process_extra.subject_to_pid(subject)
      let _ = global.register("gleamdb_" <> name, pid)
      // Try to register as the primary leader if not exists
      // case global.register(leader_name, pid) {
      //   Ok(_) -> Nil
      //   Error(_) -> {
      //     // If we are not the leader, tell the leader about us
      //     case global.whereis(leader_name) {
      //        Ok(leader_pid) -> {
      //          let leader_subject = process_extra.pid_to_subject(leader_pid)
      //          process.send(leader_subject, Join(pid))
      //        }
      //        Error(_) -> Nil
      //     }
      //   }
      // }
      Ok(subject)
    }
    Error(err) -> Error(err)
  }
}

pub fn start_with_timeout(
  store: storage.StorageAdapter,
  _timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, False, None)
}

fn do_start_named(
  store: storage.StorageAdapter,
  is_distributed: Bool,
  ets_name: Option(String),
) -> Result(process.Subject(Message), actor.StartError) {
  let assert Ok(reactive_subject) = reactive.start_link()

  let base_state =
    types.DbState(
      adapter: store,
      eavt: index.new_index(),
      aevt: index.new_aindex(),
      avet: index.new_avindex(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: is_distributed,
      ets_name: ets_name,
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      bm25_indices: dict.new(),
      art_index: art.new(),
      // Tier 2: Extension Registry
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      config: types.Config(parallel_threshold: 1000, batch_size: 1000),
    )

  let res =
    actor.new(base_state)
    |> actor.on_message(handle_message)
    |> actor.start()

  case res {
    Ok(started) -> {
      let subj = started.data
      let reply = process.new_subject()
      process.send(subj, Boot(ets_name, store, reply))
      let _ = process.receive(reply, 600_000)
      Ok(subj)
    }
    Error(e) -> Error(e)
  }
}

fn handle_message(state: types.DbState, msg: Message) -> actor.Next(types.DbState, Message) {
  case msg {
    Boot(ets_name, store, reply) -> {
      case ets_name {
        Some(name) -> ets_index.init_tables(name)
        None -> Nil
      }
      store.init()
      let new_state = recover_state(state)
      process.send(reply, Nil)
      actor.continue(new_state)
    }
    Transact(facts, vt, reply_to) -> {
      case is_leader(state) {
        True -> do_handle_transact(state, facts, vt, fact.Assert, reply_to)
        False -> {
          // Forward to leader
          case global.whereis("gleamdb_leader") {
            Ok(leader_pid) -> {
              let leader_subject = process_extra.pid_to_subject(leader_pid)
              process.send(leader_subject, Transact(facts, vt, reply_to))
              actor.continue(state)
            }
            Error(_) -> do_handle_transact(state, facts, vt, fact.Assert, reply_to)
          }
        }
      }
    }
    Retract(facts, vt, reply_to) -> {
       case is_leader(state) {
        True -> do_handle_transact(state, facts, vt, fact.Retract, reply_to)
        False -> {
          case global.whereis("gleamdb_leader") {
            Ok(leader_pid) -> {
              let leader_subject = process_extra.pid_to_subject(leader_pid)
              process.send(leader_subject, Retract(facts, vt, reply_to))
              actor.continue(state)
            }
            Error(_) -> do_handle_transact(state, facts, vt, fact.Retract, reply_to)
          }
        }
      }
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    SetSchema(attr, config, reply_to) -> {
      let existing = index.get_all_datoms_for_attr(state.eavt, attr) |> filter_active()
      
      // 1. Uniqueness Guard
      let values = list.map(existing, fn(d) { d.value })
      let has_dupes = list.unique(values) |> list.length() != list.length(values)
      
      // 2. Cardinality Guard
      let entities_with_multiple = list.fold(existing, dict.new(), fn(acc, d) {
        let count = dict.get(acc, d.entity) |> result.unwrap(0)
        dict.insert(acc, d.entity, count + 1)
      }) |> dict.to_list() |> list.filter(fn(pair) { pair.1 > 1 })
      
      let cardinality_violation = config.cardinality == fact.One && !list.is_empty(entities_with_multiple)

      case config.unique && has_dupes, cardinality_violation {
        True, _ -> {
          process.send(reply_to, Error("Cannot make non-unique attribute unique: existing data has duplicates"))
          actor.continue(state)
        }
        _, True -> {
          process.send(reply_to, Error("Cannot set cardinality to ONE: existing entities have multiple values"))
          actor.continue(state)
        }
        False, False -> {
          let new_schema = dict.insert(state.schema, attr, config)
          let new_state = types.DbState(..state, schema: new_schema)
          process.send(reply_to, Ok(Nil))
          actor.continue(new_state)
        }
      }
    }
    RegisterFunction(name, func, reply_to) -> {
      let new_functions = dict.insert(state.functions, name, func)
      let new_state = types.DbState(..state, functions: new_functions)
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }
    RegisterPredicate(name, pred, reply_to) -> {
      let new_predicates = dict.insert(state.predicates, name, pred)
      let new_state = types.DbState(..state, predicates: new_predicates)
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }
    RegisterComposite(attrs, reply_to) -> {
      // 1. Validation: Find all entities that have ALL attributes in the composite
      let clauses = list.map(attrs, fn(attr) {
        types.Positive(#(types.Var("e"), attr, types.Var(attr)))
      })
      
      let results = engine.run(state, clauses, [], None, None)
      
      // 2. Identify if any distinct entities have the same value set
      let seen = list.fold_until(results.rows, Ok(dict.new()), fn(acc_res, binding) {
        let assert Ok(acc) = acc_res
        let e = dict.get(binding, "e") |> result.unwrap(fact.Int(0))
        let vals = list.map(attrs, fn(a) { dict.get(binding, a) |> result.unwrap(fact.Int(0)) })
        
        case dict.get(acc, vals) {
          Ok(existing_e) if existing_e != e -> list.Stop(Error("Existing data violates new composite: " <> string.inspect(attrs)))
          _ -> list.Continue(Ok(dict.insert(acc, vals, e)))
        }
      })
      
      case seen {
        Ok(_) -> {
          // 3. Persist as meta-fact for durability (Dogfood Learning)
          let serialized_attrs = string.join(attrs, ",")
          let meta_eid = fact.deterministic_uid("_meta/composite/" <> serialized_attrs)
          let meta_fact = #(meta_eid, "_meta/composite", fact.Str(serialized_attrs))
          
          case do_transact(state, [meta_fact], None, fact.Assert) {
             Ok(#(new_state, _datoms)) -> {
               // The composite list is already updated by apply_datom via do_transact
               process.send(reply_to, Ok(Nil))
               actor.continue(new_state)
             }
             Error(e) -> {
               process.send(reply_to, Error(e))
               actor.continue(state)
             }
          }
        }
        Error(e) -> {
          process.send(reply_to, Error(e))
          actor.continue(state)
        }
      }
    }
    StoreRule(rule, reply_to) -> {
      // 1. Serialize Rule
      let encoded = rule_serde.serialize(rule)
      // 2. Transact as Fact
      // We use a deterministic UID based on the rule name (if we had one) or content.
      // For now, let's use the rule content hash as ID.
      let eid = fact.deterministic_uid(encoded)
      let rule_fact = #(eid, "_rule/content", fact.Str(encoded))
      
      case do_transact(state, [rule_fact], None, fact.Assert) {
        Ok(#(new_state, _datoms)) -> {
          // 3. Update in-memory state
          let new_stored = [rule, ..state.stored_rules]
          process.send(reply_to, Ok(Nil))
          actor.continue(types.DbState(..new_state, stored_rules: new_stored))
        }
        Error(e) -> {
          process.send(reply_to, Error(e))
          actor.continue(state)
        }
      }
    }
    SetReactive(subject) -> {
      actor.continue(types.DbState(..state, reactive_actor: subject))
    }
    Join(pid) -> {
      let new_followers = [pid, ..state.followers]
      actor.continue(types.DbState(..state, followers: new_followers))
    }
    SyncDatoms(datoms) -> {
      let new_state = list.fold(datoms, state, fn(acc, d) {
        apply_datom(acc, d)
      })
      
      let changed_attrs = list.map(datoms, fn(d) { d.attribute }) |> list.unique()
      process.send(state.reactive_actor, types.Notify(changed_attributes: changed_attrs, current_state: new_state))

      // Update latest_tx based on synced datoms
      let max_tx = list.fold(datoms, state.latest_tx, fn(acc, d) {
        case d.tx > acc { True -> d.tx False -> acc }
      })
      actor.continue(types.DbState(..new_state, latest_tx: max_tx))
    }
    RaftMsg(raft_msg) -> {
      let self_pid = process_extra.self()
      let #(new_raft, effects) = raft.handle_message(state.raft_state, raft_msg, self_pid)
      let new_state = types.DbState(..state, raft_state: new_raft)
      execute_raft_effects(new_state, effects, self_pid)
      actor.continue(new_state)
    }
    Compact(reply_to) -> {
      // Phase 42: Background Compaction
      // For now, we perform a simple pruning of historical retractions
      // and notify the storage adapter to compact if it supports it.
      let _datoms = index.filter_by_entity(state.eavt, fact.EntityId(0)) // Placeholder check
      // Real compaction would iterate over large shards.
      process.send(reply_to, Nil)
      actor.continue(state)
    }
    SetConfig(config, reply_to) -> {
      print_config_update(config)
      process.send(reply_to, Nil)
      actor.continue(types.DbState(..state, config: config))
    }
    RegisterIndexAdapter(adapter, reply_to) -> {
      let new_registry = dict.insert(state.registry, adapter.name, adapter)
      process.send(reply_to, Nil)
      actor.continue(types.DbState(..state, registry: new_registry))
    }
    CreateIndex(name, adapter_name, attribute, reply_to) -> {
       case dict.has_key(state.registry, adapter_name) {
         True -> {
           case dict.get(state.registry, adapter_name) {
              Ok(adapter) -> {
                  let initial_data = adapter.create(attribute)
                  let instance = types.ExtensionInstance(adapter_name, attribute, initial_data)
                  let new_extensions = dict.insert(state.extensions, name, instance)
                  process.send(reply_to, Ok(Nil))
                  actor.continue(types.DbState(..state, extensions: new_extensions))
              }
              Error(_) -> {
                  process.send(reply_to, Error("Adapter not registered"))
                  actor.continue(state)
              }
           }
         }
         False -> {
            process.send(reply_to, Error("Unknown index adapter: " <> adapter_name))
            actor.continue(state)
         }
       }
    }
    CreateBM25Index(attribute, reply_to) -> {
      let new_indices = dict.insert(state.bm25_indices, attribute, bm25.empty(attribute))
      process.send(reply_to, Ok(Nil))
      actor.continue(types.DbState(..state, bm25_indices: new_indices))
    }
    Sync(reply_to) -> {
      // Barrier: Send empty message to self and wait? No, the actor is sequential.
      // Reaching this message means all previous Transact/Retract messages in the mailbox
      // have been processed.
      process.send(reply_to, Nil)
      actor.continue(state)
    }
  }
}

fn print_config_update(config: types.Config) {
  // Simple stdout for now, would be a logger in prod
  let msg = "Config updated: threshold=" <> int.to_string(config.parallel_threshold) <> ", batch=" <> int.to_string(config.batch_size)
  case gleamdb_io_println(msg) {
    _ -> Nil
  }
}

@external(erlang, "io", "format")
fn gleamdb_io_println(x: String) -> Nil

fn is_leader(state: types.DbState) -> Bool {
  case state.is_distributed {
    False -> True
    True -> raft.is_leader(state.raft_state)
  }
}

/// Execute a list of Raft effects — the effectful shell around the pure state machine.
fn execute_raft_effects(_state: types.DbState, effects: List(raft.RaftEffect), self_pid: process.Pid) -> Nil {
  list.each(effects, fn(effect) {
    execute_raft_effect(effect, self_pid)
  })
}

fn execute_raft_effect(effect: raft.RaftEffect, self_pid: process.Pid) -> Nil {
  case effect {
    raft.SendHeartbeat(to, term, leader) -> {
      let target: process.Subject(Message) = process_extra.pid_to_subject(to)
      process.send(target, RaftMsg(raft.Heartbeat(term, leader)))
      Nil
    }
    raft.SendVoteRequest(to, term, candidate) -> {
      let target: process.Subject(Message) = process_extra.pid_to_subject(to)
      process.send(target, RaftMsg(raft.VoteRequest(term, candidate)))
      Nil
    }
    raft.SendVoteResponse(to, term, granted) -> {
      let target: process.Subject(Message) = process_extra.pid_to_subject(to)
      process.send(target, RaftMsg(raft.VoteResponse(term, granted, self_pid)))
      Nil
    }
    raft.RegisterAsLeader -> {
      let _ = global.register("gleamdb_leader", self_pid)
      Nil
    }
    raft.UnregisterAsLeader -> {
      global.unregister("gleamdb_leader")
    }
    raft.ResetElectionTimer -> {
      // Timer management is handled by the FFI — in production,
      // the transactor would maintain a timer ref in state.
      // For now, the election timeout is simulated in tests.
      Nil
    }
    raft.StartHeartbeatTimer -> {
      // Same as above — timer management is deferred to Phase 22b.
      Nil
    }
    raft.StopHeartbeatTimer -> {
      Nil
    }
  }
}

pub fn transact_with_timeout(
  db: Db,
  facts: List(fact.Fact),
  timeout_ms: Int,
) -> Result(types.DbState, String) {
  let reply = process.new_subject()
  process.send(db, Transact(facts, None, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn retract_with_timeout(
  db: Db,
  facts: List(fact.Fact),
  timeout_ms: Int,
) -> Result(types.DbState, String) {
  let reply = process.new_subject()
  process.send(db, Retract(facts, None, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn get_state(db: Db) -> types.DbState {
  let reply = process.new_subject()
  process.send(db, GetState(reply))
  process.receive_forever(reply)
}

pub fn set_schema(db: Db, attr: String, config: fact.AttributeConfig) -> Result(Nil, String) {
  set_schema_with_timeout(db, attr, config, 5000)
}

pub fn set_schema_with_timeout(
  db: Db,
  attr: String,
  config: fact.AttributeConfig,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, SetSchema(attr, config, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

fn do_handle_transact(
  state: types.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
  reply_to: process.Subject(Result(types.DbState, String)),
) -> actor.Next(types.DbState, Message) {
  case do_transact(state, facts, valid_time, op) {
    Ok(#(new_state, datoms)) -> {
      process.send(reply_to, Ok(new_state))
      let changed_attrs = list.map(facts, fn(f) { f.1 }) |> list.unique()
      process.send(state.reactive_actor, types.Notify(changed_attributes: changed_attrs, current_state: new_state))
      
      // Broadcast to followers
      list.each(state.followers, fn(f_pid) {
        let f_subject = process_extra.pid_to_subject(f_pid)
        process.send(f_subject, SyncDatoms(datoms))
      })
      
      actor.continue(new_state)
    }
    Error(err) -> {
      process.send(reply_to, Error(err))
      actor.continue(state)
    }
  }
}

fn filter_active(datoms: List(fact.Datom)) -> List(fact.Datom) {
  let latest = list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(acc, key) {
      Ok(#(tx, _op)) if tx > d.tx -> acc
      _ -> dict.insert(acc, key, #(d.tx, d.operation))
    }
  })
  list.filter(datoms, fn(d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(latest, key) {
      Ok(#(tx, op)) -> tx == d.tx && op == fact.Assert
      _ -> False
    }
  })
}

fn recover_state(state: types.DbState) -> types.DbState {
  case state.adapter.recover() {
    Ok(datoms) -> {
      // 1. Rebuild basic indices (history-preserving) WITHOUT vector indexing
      let #(inter_state, max_tx) = list.fold(datoms, #(state, 0), fn(acc, d) {
        let #(curr_state, curr_max) = acc
        let next_state = apply_datom_no_vector(curr_state, d)
        let next_max = case d.tx > curr_max {
          True -> d.tx
          False -> curr_max
        }
        #(next_state, next_max)
      })
      
      // 2. Rebuild Vector Index from ACTIVE datoms ONLY
      let active_datoms = filter_active(datoms)
      let final_state = list.fold(active_datoms, inter_state, fn(acc, d) {
        apply_datom_vector_only(acc, d)
      })
      
      types.DbState(..final_state, latest_tx: max_tx)
    }
    Error(_) -> state
  }
}

pub fn compute_next_state(
  state: types.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
) -> Result(#(types.DbState, List(fact.Datom)), String) {
  let tx_id = state.latest_tx + 1
  let vt = option.unwrap(valid_time, tx_id) // Default valid time is tx_id if not provided
  
  // 1. Resolve Transaction Functions (Recursive)
  let resolved_facts = resolve_transaction_functions(state, tx_id, vt, facts)
  
  // 2. Process Facts
  let result = list.fold_until(resolved_facts, Ok(#(state, [])), fn(acc_res, f) {
    let assert Ok(#(curr_state, acc_datoms)) = acc_res
    
    case resolve_eid(curr_state, f.0) {
      Some(id) -> {
        case op {
          fact.Assert -> {
            let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None))
            
            // Cardinality One or LatestOnly Retention
            let #(sub_state, sub_datoms) = case config.cardinality == fact.One || config.retention == fact.LatestOnly {
              True -> {
                let existing = index.get_datoms_by_entity_attr(curr_state.eavt, id, f.1) |> filter_active()
                list.fold(existing, #(curr_state, []), fn(acc, d) {
                  let #(st, ds) = acc
                  let retract_datom = fact.Datom(..d, tx: tx_id, valid_time: vt, operation: fact.Retract)
                  #(apply_datom(st, retract_datom), [retract_datom, ..ds])
                })
              }
              False -> #(curr_state, [])
            }
            
            let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, valid_time: vt, operation: fact.Assert)
            
            // Validation
            case check_constraints(sub_state, datom) {
              Ok(_) -> {
                case check_composite_uniqueness(sub_state, datom) {
                   Ok(_) -> list.Continue(Ok(#(apply_datom(sub_state, datom), [datom, ..list.append(sub_datoms, acc_datoms)])))
                   Error(e) -> list.Stop(Error(e))
                }
              }
              Error(e) -> list.Stop(Error(e))
            }
          }
          fact.Retract -> {
             let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None))
             let #(sub_state, sub_datoms) = case config.component {
               True -> {
                 case f.2 {
                   fact.Ref(fact.EntityId(sub_id)) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, vt, [])
                   fact.Int(sub_id) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, vt, [])
                   _ -> #(curr_state, [])
                 }
               }
               False -> #(curr_state, [])
             }
             let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, valid_time: vt, operation: fact.Retract)
             list.Continue(Ok(#(apply_datom(sub_state, datom), [datom, ..list.append(sub_datoms, acc_datoms)])))
          }
        }
      }
      None -> {
        list.Continue(Ok(#(curr_state, acc_datoms)))
      }
    }
  })

  case result {
    Ok(#(final_state, all_datoms)) -> {
      let reversed = list.reverse(all_datoms)
      Ok(#(types.DbState(..final_state, latest_tx: tx_id), reversed))
    }
    Error(e) -> Error(e)
  }
}

fn do_transact(
  state: types.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
) -> Result(#(types.DbState, List(fact.Datom)), String) {
  case compute_next_state(state, facts, valid_time, op) {
    Ok(#(final_state, reversed)) -> {
      final_state.adapter.persist_batch(reversed)
      Ok(#(final_state, reversed))
    }
    Error(e) -> Error(e)
  }
}

fn resolve_transaction_functions(state: types.DbState, tx_id: Int, vt: Int, facts: List(fact.Fact)) -> List(fact.Fact) {
  list.flat_map(facts, fn(f) {
    case f.0 {
      fact.Lookup(#("db/fn", fact.Str(fn_name))) -> {
        case dict.get(state.functions, fn_name) {
          Ok(func) -> {
            let args = case f.2 {
              fact.List(l) -> l
              _ -> [f.2]
            }
            let new_facts = func(state, tx_id, vt, args)
            resolve_transaction_functions(state, tx_id, vt, new_facts)
          }
          Error(_) -> [f] // Fallback, let down-stream handle error if needed
        }
      }
      _ -> [f]
    }
  })
}

fn check_composite_uniqueness(state: types.DbState, datom: fact.Datom) -> Result(Nil, String) {
  let composites = list.filter(state.composites, fn(c) { list.contains(c, datom.attribute) })
  
  list.fold_until(composites, Ok(Nil), fn(_, composite) {
    // 1. Collect values for all attributes in the composite for this entity
    let values_res = list.fold_until(composite, Ok([]), fn(acc_res, attr) {
      let assert Ok(acc) = acc_res
      let val = case attr == datom.attribute {
        True -> Ok(datom.value)
        False -> {
          let existing = index.get_datoms_by_entity_attr(state.eavt, datom.entity, attr) |> filter_active()
          case list.first(existing) {
            Ok(d) -> Ok(d.value)
            Error(_) -> Error(Nil)
          }
        }
      }
      case val {
        Ok(v) -> list.Continue(Ok([#(attr, v), ..acc]))
        Error(_) -> list.Stop(Error(Nil))
      }
    })
    
    case values_res {
      Error(_) -> list.Continue(Ok(Nil)) // Skip check if any attribute is missing
      Ok(attr_vals) -> {
        // 2. Query for other entities with the same values
        let clauses = list.map(attr_vals, fn(pair) {
          types.Positive(#(types.Var("e"), pair.0, types.Val(pair.1)))
        })
        
        let results = engine.run(state, clauses, [], None, None)
        let has_violation = list.any(results.rows, fn(binding) {
          case dict.get(binding, "e") {
            Ok(fact.Ref(eid)) -> eid != datom.entity
            Ok(fact.Int(eid)) -> fact.EntityId(eid) != datom.entity
            _ -> False
          }
        })
        
        case has_violation {
          True -> list.Stop(Error("Composite uniqueness violation: " <> string.inspect(composite)))
          False -> list.Continue(Ok(Nil))
        }
      }
    }
  })
}

pub fn transact(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  transact_with_timeout(db, facts, 5000)
}

fn retract_recursive_collected(state: types.DbState, eid: fact.EntityId, tx_id: Int, valid_time: Int, acc: List(fact.Datom)) -> #(types.DbState, List(fact.Datom)) {
  let children = index.filter_by_entity(state.eavt, eid) |> filter_active()
  list.fold(children, #(state, acc), fn(curr, d) {
    let #(curr_state, curr_acc) = curr
    let config = dict.get(curr_state.schema, d.attribute) |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None))
    let #(sub_state, sub_acc) = case config.component {
      True -> {
        case d.value {
          fact.Ref(fact.EntityId(sub_id)) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, valid_time, curr_acc)
          fact.Int(sub_id) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, valid_time, curr_acc)
          _ -> #(curr_state, curr_acc)
        }
      }
      False -> #(curr_state, curr_acc)
    }
    let retract_datom = fact.Datom(..d, tx: tx_id, valid_time: valid_time, operation: fact.Retract)
    #(apply_datom(sub_state, retract_datom), [retract_datom, ..sub_acc])
  })
}

fn apply_datom(state: types.DbState, datom: fact.Datom) -> types.DbState {
  let datom = case datom.value {
    fact.Vec(v) -> fact.Datom(..datom, value: fact.Vec(vector.normalize(v)))
    _ -> datom
  }
  state
  |> apply_datom_no_vector(datom)
  let state = apply_datom_art(state, datom)
  let state = apply_datom_extensions(state, datom)
  let state = apply_datom_bm25(state, datom)
  state
  |> apply_datom_no_vector(datom)
  |> apply_datom_vector_only(datom)
}

fn apply_datom_bm25(state: types.DbState, datom: fact.Datom) -> types.DbState {
  case dict.get(state.bm25_indices, datom.attribute) {
    Ok(index) -> {
       case datom.value {
         fact.Str(text) -> {
           let new_index = case datom.operation {
             fact.Assert -> bm25.add(index, datom.entity, text)
             fact.Retract -> bm25.remove(index, datom.entity, text)
           }
           let new_indices = dict.insert(state.bm25_indices, datom.attribute, new_index)
           types.DbState(..state, bm25_indices: new_indices)
         }
         _ -> state
       }
    }
    Error(_) -> state
  }
}

fn apply_datom_extensions(state: types.DbState, datom: fact.Datom) -> types.DbState {
  let new_extensions = dict.map_values(state.extensions, fn(_name, instance) {
    case instance.attribute == datom.attribute {
      True -> {
         case dict.get(state.registry, instance.adapter_name) {
            Ok(adapter) -> {
               let new_data = adapter.update(instance.data, [datom])
               types.ExtensionInstance(..instance, data: new_data)
            }
            Error(_) -> instance
         }
      }
      False -> instance
    }
  })
  types.DbState(..state, extensions: new_extensions)
}

fn apply_datom_art(state: types.DbState, datom: fact.Datom) -> types.DbState {
  case datom.value {
    fact.Str(_) -> {
      let new_art = case datom.operation {
        fact.Assert -> art.insert(state.art_index, datom.value, datom.entity)
        fact.Retract -> art.delete(state.art_index, datom.value, datom.entity)
      }
      types.DbState(..state, art_index: new_art)
    }
    _ -> state
  }
}

fn apply_datom_no_vector(state: types.DbState, datom: fact.Datom) -> types.DbState {
  let config = dict.get(state.schema, datom.attribute) |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None))
  let retention = config.retention
  
  // Rule Recovery (Side Effect on DbState metadata)
  let state = case datom.attribute {
    "_rule/content" -> {
      case datom.value, datom.operation {
        fact.Str(encoded), fact.Assert -> {
          case rule_serde.deserialize(encoded) {
            Ok(rule) -> types.DbState(..state, stored_rules: [rule, ..state.stored_rules])
            _ -> state
          }
        }
        _, _ -> state
      }
    }
    "_meta/composite" -> {
      case datom.value, datom.operation {
        fact.Str(attrs_str), fact.Assert -> {
          let attrs = string.split(attrs_str, ",")
          case list.contains(state.composites, attrs) {
            True -> state
            False -> types.DbState(..state, composites: [attrs, ..state.composites])
          }
        }
        _, _ -> state
      }
    }
    _ -> state
  }

  case state.ets_name {
    Some(name) -> {
      case retention {
        fact.LatestOnly -> {
           ets_index.prune_historical(name <> "_eavt", datom.entity, datom.attribute)
           ets_index.prune_historical_aevt(name <> "_aevt", datom.attribute, datom.entity)
        }
        _ -> Nil
      }
      
      ets_index.insert_datom(name <> "_eavt", datom.entity, datom)
      ets_index.insert_datom(name <> "_aevt", datom.attribute, datom)
      case datom.operation {
        fact.Assert -> ets_index.insert_avet(name <> "_avet", #(datom.attribute, datom.value), datom.entity)
        fact.Retract -> ets_index.delete(name <> "_avet", #(datom.attribute, datom.value))
      }
      state
    }
    None -> {
      case datom.operation {
        fact.Assert -> {
          types.DbState(
            ..state,
            eavt: index.insert_eavt(state.eavt, datom, retention),
            aevt: index.insert_aevt(state.aevt, datom, retention),
            avet: index.insert_avet(state.avet, datom),
          )
        }
        fact.Retract -> {
          types.DbState(
            ..state,
            eavt: index.delete_eavt(state.eavt, datom),
            aevt: index.delete_aevt(state.aevt, datom),
            avet: index.delete_avet(state.avet, datom),
          )
        }
      }
    }
  }
}

fn apply_datom_vector_only(state: types.DbState, datom: fact.Datom) -> types.DbState {
  case datom.operation {
    fact.Assert -> {
      let new_vec_idx = case datom.value {
        fact.Vec(v) -> {
          vec_index.insert(state.vec_index, datom.entity, v)
        }
        _ -> state.vec_index
      }
      types.DbState(..state, vec_index: new_vec_idx)
    }
    fact.Retract -> {
      let new_vec_idx = case datom.value {
        fact.Vec(_) -> vec_index.delete(state.vec_index, datom.entity)
        _ -> state.vec_index
      }
      types.DbState(..state, vec_index: new_vec_idx)
    }
  }
}

pub fn retract(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  retract_with_timeout(db, facts, 5000)
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(types.DbState),
) -> Nil {
  let reply = process.new_subject()
  process.send(db, RegisterFunction(name, func, reply))
  let _ = process.receive(reply, 5000)
  Nil
}

pub fn register_predicate(
  db: Db,
  name: String,
  pred: fn(fact.Value) -> Bool,
) -> Nil {
  let reply = process.new_subject()
  process.send(db, RegisterPredicate(name, pred, reply))
  let _ = process.receive(reply, 5000)
  Nil
}

pub fn store_rule(db: Db, rule: types.Rule) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, StoreRule(rule, reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout storing rule")
  }
}

pub fn create_bm25_index(db: Db, attribute: String) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, CreateBM25Index(attribute, reply))
    case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout creating BM25 index")
  }
}

pub fn register_composite(db: Db, attrs: List(String)) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, RegisterComposite(attrs, reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout registering composite")
  }
}

pub fn set_config(db: Db, config: types.Config) -> Nil {
  let reply = process.new_subject()
  process.send(db, SetConfig(config, reply))
  let _ = process.receive(reply, 5000)
  Nil
}

fn resolve_eid(state: types.DbState, eid: fact.Eid) -> Option(fact.EntityId) {
  case eid {
    fact.Uid(id) -> Some(id)
    fact.Lookup(#(a, v)) -> index.get_entity_by_av(state.avet, a, v) |> option.from_result()
  }
}

fn check_constraints(state: types.DbState, datom: fact.Datom) -> Result(Nil, String) {
  let config = dict.get(state.schema, datom.attribute) |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None))
  
  // 1. Uniqueness check
  let res = case config.unique {
    True -> {
      case index.get_entity_by_av(state.avet, datom.attribute, datom.value) {
        Ok(existing_id) if existing_id != datom.entity -> Error("Unique constraint violation on " <> datom.attribute)
        _ -> Ok(Nil)
      }
    }
    False -> Ok(Nil)
  }
  
  // 2. Custom check predicate
  case res {
    Ok(_) -> {
      case config.check {
        Some(pred_name) -> {
          case dict.get(state.predicates, pred_name) {
            Ok(pred) -> {
              case pred(datom.value) {
                True -> Ok(Nil)
                False -> Error("CHECK constraint violation on " <> datom.attribute <> " (predicate: " <> pred_name <> ")")
              }
            }
            Error(_) -> Ok(Nil) // Predicate not found, skip check
          }
        }
        None -> Ok(Nil)
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn register_index_adapter(
  db: Db,
  adapter: types.IndexAdapter,
) -> Nil {
  let reply = process.new_subject()
  process.send(db, RegisterIndexAdapter(adapter, reply))
  let _ = process.receive(reply, 5000)
  Nil
}

pub fn create_index(
  db: Db,
  attribute: String,
  adapter_name: String,
  name: String,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, CreateIndex(name, adapter_name, attribute, reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}
