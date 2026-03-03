import gleam/erlang/process.{type Subject}
import gleam/dict
import gleam/list
import gleam/io
import gleam/int
import gswarm/registry_actor.{type Message as RegistryMessage, CollapseShard}
import gleamdb/sharded.{type ShardedDb}
import gleamdb/transactor

pub fn start(db: ShardedDb, registry: Subject(RegistryMessage), interval_ms: Int) {
  process.spawn(fn() {
    loop(db, registry, interval_ms)
  })
}

fn loop(db: ShardedDb, registry: Subject(RegistryMessage), interval_ms: Int) {
  process.sleep(interval_ms)
  
  // Check all shards except Primary (0)
  let shards = dict.to_list(db.shards)
  list.each(shards, fn(pair) {
    let #(id, shard_subject) = pair
    case id == 0 {
      True -> Nil
      False -> {
        // Try to sync with shard to verify health
        let reply = process.new_subject()
        process.send(shard_subject, transactor.Sync(reply))
        case process.receive(reply, 1000) {
          Ok(_) -> Nil // Shard is healthy
          Error(_) -> {
            io.println("⚠️ Shard Monitor: Shard " <> int.to_string(id) <> " UNRESPONSIVE. Initiating Failover to Primary.")
            process.send(registry, CollapseShard(virtual_id: id, physical_id: 0))
          }
        }
      }
    }
  })
  
  loop(db, registry, interval_ms)
}
