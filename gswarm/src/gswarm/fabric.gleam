import gleam/io
import gleam/erlang/process
import gswarm/node.{type NodeContext}
import gleamdb

pub fn join_sharded_fabric(role: node.NodeRole, cluster_id: String, shard_count: Int) -> Result(node.ShardedContext, String) {
  node.start_sharded(role, cluster_id, shard_count)
}

pub fn join_fabric(role: node.NodeRole, cluster_id: String) -> Result(NodeContext, String) {
  let res = node.start(role, cluster_id)
  
  case res {
    Ok(ctx) -> {
      case role {
        node.Follower -> {
          // Spawn Raft Role Watcher
          process.spawn_unlinked(fn() {
            role_watcher_loop(ctx, False)
          })
          Ok(ctx)
        }
        node.Leader | node.LeaderEphemeral | node.Lean -> Ok(ctx)
      }
    }
    Error(e) -> Error(e)
  }
}

import gswarm/ticker
import gswarm/reflex

fn role_watcher_loop(ctx: NodeContext, was_leader: Bool) {
  process.sleep(1000)
  
  // Ask GleamDB about its Raft state
  let is_leader = gleamdb.is_leader(ctx.db)
  
  case was_leader, is_leader {
    False, True -> {
      io.println("👑 Fabric: I am now the LEADER (via Raft). Starting sovereign reflexes...")
      
      // Autohealing: Resume simulation for the primary markets
      ticker.start_ticker(ctx.db, "m_1")
      ticker.start_ticker(ctx.db, "m_2")
      reflex.spawn_market_watcher(ctx.db, "m_1")
      reflex.spawn_market_watcher(ctx.db, "m_2")
      
      role_watcher_loop(ctx, True)
    }
    True, False -> {
      io.println("📉 Fabric: I am no longer the LEADER. Stepping down...")
      // In a full implementation, we would stop tickers here.
      role_watcher_loop(ctx, False)
    }
    _, _ -> role_watcher_loop(ctx, is_leader)
  }
}

pub fn broadcast_ping(ctx: NodeContext) -> Nil {
  // A simple liveness check across the mesh
  case ctx.role {
    node.Leader | node.LeaderEphemeral | node.Lean -> Nil // Leader doesn't ping, it rules.
    node.Follower -> {
      // Future: Implement keepalive to leader
      Nil
    }
  }
}
