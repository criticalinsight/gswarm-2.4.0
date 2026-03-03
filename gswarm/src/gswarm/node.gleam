import gleam/otp/actor
import gleam/option.{Some, None}
import gleam/string
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/storage/mnesia
import gleamdb/sharded
import gswarm/shard_manager.{type ShardRegistry}
import gswarm/registry_actor

pub type NodeRole {
  Leader
  Follower
  LeaderEphemeral
  Lean        // Phase 41: Optimized for low resource usage
}

pub type NodeContext {
  NodeContext(
    role: NodeRole,
    db: gleamdb.Db,
    id: String
  )
}

pub type ShardedContext {
  ShardedContext(
    role: NodeRole,
    db: sharded.ShardedDb,
    cluster_id: String,
    registry: ShardRegistry,
    registry_actor: process.Subject(registry_actor.Message)
  )
}

pub fn get_primary(ctx: ShardedContext) -> gleamdb.Db {
  let assert Ok(db) = dict.get(ctx.db.shards, 0)
  db
}

pub fn start_sharded(role: NodeRole, cluster_id: String, shard_count: Int) -> Result(ShardedContext, String) {
  case role {
    Leader -> {
      case sharded.start_sharded(cluster_id, shard_count, Some(mnesia.adapter())) {
        Ok(db) -> {
          let registry = shard_manager.new_registry(shard_count)
          let assert Ok(actor) = registry_actor.start(shard_count)
          
          // Phase 11: Initialize Speculative Mirror Shard (99)
          let mirror_shard_id = sharded.mirror_shard_id
          let mirror_cluster_id = cluster_id <> "_s" <> string.inspect(mirror_shard_id)
          let assert Ok(mirror_db) = gleamdb.start_distributed(mirror_cluster_id, Some(mnesia.adapter()))
          let db_with_mirror = sharded.ShardedDb(..db, shards: dict.insert(db.shards, mirror_shard_id, mirror_db))
          
          Ok(ShardedContext(role, db_with_mirror, cluster_id, registry, actor))
        }
        Error(e) -> Error("Failed to start sharded leader: " <> e)
      }
    }
    Lean -> {
       // Phase 41: Local sharding for Lean mode (Ephemeral/RAM-only for speed/dev)
       case sharded.start_local_sharded(cluster_id, shard_count, None) {
        Ok(db) -> {
          let registry = shard_manager.new_registry(shard_count)
          let assert Ok(actor) = registry_actor.start(shard_count)
          Ok(ShardedContext(role, db, cluster_id, registry, actor))
        }
        Error(e) -> Error("Failed to start lean sharded leader: " <> e)
      }
    }
    _ -> Error("Follower/Ephemeral sharding not fully implemented in start_sharded")
  }
}


pub fn start(role: NodeRole, cluster_id: String) -> Result(NodeContext, String) {
  case role {
    Leader ->
      case gleamdb.start_distributed(cluster_id, Some(mnesia.adapter())) {
        Ok(db) -> Ok(NodeContext(Leader, db, cluster_id))
        Error(e) -> Error(string_error(e))
      }
    Follower ->
      case gleamdb.connect(cluster_id) {
        Ok(db) -> Ok(NodeContext(Follower, db, cluster_id))
        Error(e) -> Error(e)
      }
    Lean ->
      case gleamdb.start_named(cluster_id, Some(mnesia.adapter())) {
        Ok(db) -> Ok(NodeContext(Lean, db, cluster_id))
        Error(e) -> Error(string_error(e))
      }
    LeaderEphemeral -> {
      let db = gleamdb.new()
      Ok(NodeContext(LeaderEphemeral, db, cluster_id))
    }
  }
}

pub fn promote_to_leader(ctx: NodeContext) -> Result(NodeContext, String) {
  case ctx.role {
    Leader | LeaderEphemeral | Lean -> Ok(ctx)
    Follower -> {
      // Autonomous Promotion: Restart node as Leader
      start(Leader, ctx.id)
    }
  }
}

import gleamdb/global

pub fn stop(ctx: NodeContext) {
  // Clean up global registry FIRST to avoid hangs in Erlang/global
  let _ = global.unregister("gleamdb_leader")
  let _ = global.unregister("gleamdb_" <> ctx.id)

  let assert Ok(pid) = process.subject_owner(ctx.db)
  process.unlink(pid)
  process.kill(pid)
}

pub fn stop_sharded(ctx: ShardedContext) {
  let _ = sharded.stop(ctx.db)
  
  let assert Ok(reg_pid) = process.subject_owner(ctx.registry_actor)
  process.unlink(reg_pid)
  process.kill(reg_pid)
  
  Nil
}

import gleam/io

fn string_error(err: actor.StartError) -> String {
  let msg = case err {
    actor.InitTimeout -> "Init Timeout"
    actor.InitExited(reason) -> "Init Exited: " <> string.inspect(reason)
    actor.InitFailed(reason) -> "Init Failed: " <> string.inspect(reason)
  }
  io.println("❌ Gswarm Node Start Error: " <> msg)
  msg
}
