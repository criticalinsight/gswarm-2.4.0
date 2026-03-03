import gleam/io
import argv
import gleam/list
import gleam/dict
import gleam/erlang/process
import gleam/option.{Some, None}
import gleam/float
import gleam/int
import gswarm/fabric
import gswarm/node
import gswarm/supervisor
import gswarm/analyst
import gswarm/news_feed
import gswarm/correlator
import gswarm/result_fact
import gswarm/market_feed

import gswarm/cross_market
import gswarm/ingest_batcher
import gswarm/pruner
import gswarm/http
import gswarm/leaderboard
import gswarm/targeter
import gswarm/types

import gswarm/activity_feed
import gswarm/insider_store
import gswarm/graph_intel
import gswarm/notifier
import gswarm/polymarket_crawler
import gswarm/news_historical
import gswarm/clustering
import gswarm/mirror
import gswarm/groomer
import gswarm/shard_monitor
import gswarm/rate_limiter

pub fn main() {
  io.println("🐝 Gswarm: Initializing Sharded Sovereign Fabric...")
  
  let arguments = argv.load().arguments
  let is_lean = list.contains(arguments, "--lean")
  
  let #(role, cluster_id) = case arguments {
    [r, c, ..] if r != "--lean" -> #(parse_role(r), c)
    [r] if r != "--lean" -> #(parse_role(r), "gswarm_mainnet")
    _ -> #(case is_lean { True -> node.Lean False -> node.Leader }, "gswarm_mainnet")
  }
  let cluster_id = case is_lean {
    True -> "lean_" <> cluster_id
    False -> cluster_id
  }

  // Phase 41: Shard collapsing for Lean mode
  let shard_count = case is_lean {
    True -> 1
    False -> 4
  }
  
  case fabric.join_sharded_fabric(role, cluster_id, shard_count) {
    Ok(ctx) -> {
      io.println("👑 Sharded Fabric started with " <> role_to_string(role) <> " shards: " <> cluster_id)
      
      // Select Primary Shard (Shard 0) for global components
      let assert Ok(primary_db) = dict.get(ctx.db.shards, 0)

      // Start Supervision Tree on primary
      let assert Ok(_) = supervisor.start(primary_db)

      // Phase 30: Register market data constraints (v2.0.0)
      let _ = graph_intel.register_market_constraints(ctx)

      // News Feed (Global)
      news_feed.start_news_feed(primary_db)
      correlator.start_correlator(primary_db)
      result_fact.start_result_checker(primary_db)

      // 2. Start Insider Store (Phase 49)
      let assert Ok(insider_actor) = insider_store.start(primary_db)
      
      // 2b. Start Notifier (Telegram)
      let assert Ok(notifier_actor) = notifier.start()

      // Start Batchers and Pruners for all shards
      let batchers = list.map(dict.to_list(ctx.db.shards), fn(pair) {
        let #(id, db) = pair
        let assert Ok(batcher) = ingest_batcher.start(db, ctx.registry_actor, insider_actor)
        // Phase 45: Prune old ticks after 1 hour, check every 30 seconds
        let assert Ok(_) = pruner.start(db, 3_600_000, 30_000, "tick/timestamp")
        #(id, batcher)
      }) |> dict.from_list

      // Phase 17: Causal Analyst (Event-Driven)
      let assert Ok(analyst_actor) = analyst.start_analyst(ctx.db)

      // --- PHASE 50: Advanced Amkabot Integration ---
      
      // 1. Start Leaderboard Actor (GleamDB Sovereign Fabric 🧙🏾‍♂️)
      let assert Ok(lb_actor) = leaderboard.start(primary_db)
      io.println("🏆 Leaderboard Active (GleamDB Sovereign Fabric 🧙🏾‍♂️)")
      process.send(notifier_actor, notifier.RegisterLeaderboard(lb_actor))
      process.send(notifier_actor, notifier.RegisterDb(primary_db))
      
      // Phase 20: Sovereign Targeter (Dynamic Intelligence)
      let policy = types.TargetingPolicy(
        min_roi: 50.0,
        min_invested: 999_999_999.0, // ROI is the only signal
        target_price_min: -1.0,      // Disable price triggers
        target_price_max: -1.0,
        exclude_legacy_traders: True
      )

      let notify_fn = fn(event: types.Event) {
        process.send(notifier_actor, notifier.Notify(event))
        Nil
      }

      let assert Ok(targeter_actor) = targeter.start(policy, notify_fn)
      
      // Subscribe Targeter to Leaderboard Stats updates
      process.spawn(fn() {
        stats_loop(lb_actor, targeter_actor)
      })

      // 3. PolyMarket Feed
      // Dynamically discover active markets to avoid 404s
      let polymarket_ids = case market_feed.fetch_active_tokens() {
        Ok(ids) if ids != [] -> ids
        _ -> {
          io.println("⚠️ PolyMarket: Discovery failed or empty, using fallback.")
          ["101676997363687199724245607342877036148401850938023978421879460310389391082353"] // Live token ID
        }
      }
      io.println("🔵 PolyMarket: Discovered " <> int.to_string(list.length(polymarket_ids)) <> " active tokens.")
      
      // We pick a shard for the feed (e.g. Shard 0)
      let assert Ok(pm_batcher) = dict.get(batchers, 0)
      
      market_feed.start_polymarket_feed(pm_batcher, polymarket_ids, None, Some(analyst_actor), notifier_actor)

      // 4. Activity Feed (Leaderboard)
      // Discover top traders to track
      let active_users = case activity_feed.fetch_leaderboard() {
        Ok(users) -> users
        Error(e) -> {
          io.println("⚠️ ActivityFeed: Discovery failed (" <> e <> "), using fallback.")
          ["0x4bFb41d5B3570DeFd03C39a9A4D8D6D04C96E631"]
        }
      }
      io.println("🕵️ ActivityFeed: Tracking " <> int.to_string(list.length(active_users)) <> " traders.")
      activity_feed.start_with_dedup(lb_actor, active_users)


      // Cross-Market Intel (Scatter-Gather across shards)
      let assert Ok(_) = cross_market.start_link(ctx)
      
      // Phase 46: Operability Dashboard
      io.println("📊 Starting Metrics Dashboard on port 8085...")
      let metrics_limiter = rate_limiter.start(100) // Higher limit for metrics
      http.start_server(8085, ctx, lb_actor, insider_actor, metrics_limiter)
      
      // Phase 44: Probabilistic Metrics Monitor
      process.spawn(fn() {
        loop_flush(lb_actor)
      })

      // Phase 32: Start periodic Graph Intelligence scans (v2.0.0)
      graph_intel.start_periodic_scan(ctx, 300_000)

      // Phase 9: Start Mass Crawler and Historical News Ingestion
      polymarket_crawler.start_crawler(primary_db)
      news_historical.ingest_historical_news(primary_db, int.to_float(erlang_system_time()) |> float.truncate, 500)
      
      // Phase 10: Start behavioral clustering (hourly cycle)
      clustering.start_clustering_loop(primary_db, 3_600_000)
      
      // Phase 11: Start Mirror Oracle
      let _ = mirror.start(ctx.db, lb_actor)
      
      // Phase 12: Resilience & Production Hardening
      let limiter = rate_limiter.start(10) // 10 req/s
      groomer.start_groomer(primary_db, 3_600_000, 86_400_000) // Prune 1h old every 24h
      shard_monitor.start(ctx.db, ctx.registry_actor, 60_000) // Monitor health every 1m
      
      // Start the HTTP server on port 8080
      io.println("🚀 Gswarm: Sovereign Console starting on port 8080...")
      http.start_server(8080, ctx, lb_actor, insider_actor, limiter)

      process.sleep_forever()
    }
    Error(e) -> {
      io.println("❌ Failed to join fabric: " <> e)
    }
  }
}

fn loop_flush(lb_actor) {
  process.sleep(60_000)
  process.send(lb_actor, leaderboard.Flush)
  loop_flush(lb_actor)
}

fn parse_role(r: String) -> node.NodeRole {
  case r {
    "leader" -> node.Leader
    "follower" -> node.Follower
    _ -> node.Leader
  }
}

fn role_to_string(r: node.NodeRole) -> String {
  case r {
    node.Leader -> "LEADER"
    node.Follower -> "FOLLOWER"
    node.Lean -> "LEAN NODE (RESTRICTED)"
    node.LeaderEphemeral -> "LEADER (EPHEMERAL)"
  }
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}

fn stats_loop(lb_actor, targeter) {
  let receiver = process.new_subject()
  process.send(lb_actor, leaderboard.Subscribe(receiver))
  do_stats_loop(receiver, targeter)
}

fn do_stats_loop(receiver, targeter) {
  let stats = process.receive(receiver, 600_000)
  case stats {
    Ok(s) -> {
      process.send(targeter, targeter.StatsUpdate(s))
      do_stats_loop(receiver, targeter)
    }
    Error(_) -> Nil
  }
}
