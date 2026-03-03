
import gleam/io
import gleam/list
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
  io.println("🔍 Gswarm: Auditing DB content (Direct Attribute Probing)...")
  
  let cluster_id = "gswarm_mainnet"
  let shard_count = 4
  
  case fabric.join_sharded_fabric(node.Leader, cluster_id, shard_count) {
    Ok(ctx) -> {
      let all_shards = dict.to_list(ctx.db.shards)
      
      let attributes_to_probe = ["trader/pnl", "trader/roi", "trader/id", "market/id", "tick/price"]
      
      list.each(all_shards, fn(shard_pair) {
        let #(shard_id, db) = shard_pair
        io.println("\n🔹 Shard [" <> int.to_string(shard_id) <> "]:")
        
        list.each(attributes_to_probe, fn(attr) {
          let query = [
            db_types.Positive(#(db_types.Var("e"), attr, db_types.Var("v")))
          ]
          let results = gleamdb.query(db, query)
          case list.length(results.rows) {
            0 -> Nil
            count -> {
              io.println("  • " <> attr <> ": " <> int.to_string(count) <> " facts")
              list.take(results.rows, 3)
              |> list.each(fn(row) {
                 case dict.get(row, "e"), dict.get(row, "v") {
                   Ok(fact.Ref(fact.EntityId(eid))), Ok(v) -> {
                      io.println("    └─ " <> int.to_string(eid) <> " | " <> string.inspect(v))
                   }
                   _, _ -> Nil
                 }
              })
            }
          }
        })
      })
      process.sleep(1000)
    }
    Error(e) -> io.println("❌ Failed to join fabric: " <> string.inspect(e))
  }
}
