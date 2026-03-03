
import gleam/io
import gleam/list
import gleam/float
import gleam/int
import gleam/string
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/shared/types as db_types
import gleamdb/fact
import gswarm/fabric
import gswarm/node

pub fn main() {
  io.println("🕵️ Gswarm: Extracting Real-World Alpha Signals (Multi-Shard)...")
  
  let cluster_id = "gswarm_mainnet"
  let shard_count = 4 // Default for non-lean
  
  case fabric.join_sharded_fabric(node.Leader, cluster_id, shard_count) {
    Ok(ctx) -> {
      io.println("✅ Joined Sharded Fabric: " <> cluster_id)
      
      let all_shards = dict.to_list(ctx.db.shards)
      io.println("📊 Querying " <> int.to_string(list.length(all_shards)) <> " shards...")
      
      list.each(all_shards, fn(shard_pair) {
        let #(shard_id, db) = shard_pair
        io.println("\n🔹 Shard [" <> int.to_string(shard_id) <> "]:")
        
        let query = [
          db_types.Positive(#(db_types.Var("t"), "trader/roi", db_types.Var("roi"))),
          db_types.Positive(#(db_types.Var("t"), "trader/pnl", db_types.Var("pnl"))),
          db_types.Positive(#(db_types.Var("t"), "trader/preds", db_types.Var("preds")))
        ]
        
        let results = gleamdb.query(db, query)
        let elite_traders = list.filter_map(results.rows, fn(row) {
          case dict.get(row, "roi"), dict.get(row, "pnl"), dict.get(row, "preds"), dict.get(row, "t") {
            Ok(fact.Float(roi)), Ok(fact.Float(pnl)), Ok(fact.Int(preds)), Ok(fact.Ref(tid)) -> {
              case roi >=. 10.0 { // Lowered to 10% to find ANY alpha first
                True -> {
                  // Connect to primary (Shard 0) to get ID if needed, but let's just use EID for now
                  let trader_id = "EID(" <> int.to_string(fact.eid_to_integer(tid)) <> ")"
                  Ok(#(trader_id, roi, pnl, preds))
                }
                False -> Error(Nil)
              }
            }
            _, _, _, _ -> Error(Nil)
          }
        })
        |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
        
        case elite_traders {
          [] -> io.println("  🔇 No alpha traders found in this shard.")
          items -> {
            io.println("  🔥 SIGNALS DETECTED:")
            list.each(items, fn(item) {
              let #(tid, roi, pnl, preds) = item
              io.println("    • Trader: " <> tid <> " | ROI: " <> float.to_string(roi) <> "% | PnL: $" <> float.to_string(pnl) <> " | Trades: " <> int.to_string(preds))
            })
          }
        }
      })
      
      process.sleep(1000) // Small grace for async cleanup
    }
    Error(e) -> io.println("❌ Failed to join fabric: " <> string.inspect(e))
  }
}
