import gleam/erlang/process
import gleam/io
import gleam/int
import gleamdb

pub fn start_groomer(db: gleamdb.Db, older_than_ms: Int, interval_ms: Int) {
  process.spawn(fn() {
    loop(db, older_than_ms, interval_ms)
  })
}

fn loop(db: gleamdb.Db, older_than_ms: Int, interval_ms: Int) {
  process.sleep(interval_ms)
  
  // Rich Hickey: "Pruning allows the system to remain lean without sacrificing sovereign identity."
  let state = gleamdb.get_state(db)
  let now = state.latest_tx // Using tx as a proxy for time for deterministic pruning
  let threshold = now - older_than_ms 
  // Note: in a real system threshold would be based on valid_time or wall-clock
  
  let sovereign = ["trader/id", "market/slug", "trader/behavioral_tag", "_rule/content", "trader/total_pnl"]
  
  io.println("🧹 Groomer: Starting maintenance cycle...")
  let pruned_count = gleamdb.prune(db, threshold, sovereign)
  io.println("🧹 Groomer: Cycle complete. Pruned " <> int.to_string(pruned_count) <> " Datoms.")
  
  loop(db, older_than_ms, interval_ms)
}
