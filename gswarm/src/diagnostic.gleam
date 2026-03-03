import gleam/io
import gleam/option.{Some}
import gleam/dict
import gleamdb
import gleamdb/sharded
import gleamdb/fact
import gleamdb/storage/mnesia

pub fn main() {
  io.println("🧪 Diagnostic: Starting distributed sharded DB with Mnesia (2 shards)...")
  case sharded.start_sharded("diag_MN", 2, Some(mnesia.adapter())) {
    Ok(db) -> {
      io.println("✅ Sharded DB started.")
      case dict.get(db.shards, 0) {
        Ok(shard) -> {
           case gleamdb.transact(shard, [#(fact.deterministic_uid("test"), "attr", fact.Str("val"))]) {
             Ok(_) -> io.println("✅ Transaction on Shard 0 successful.")
             Error(e) -> io.println("❌ Transaction failed: " <> e)
           }
        }
        Error(_) -> io.println("❌ Shard 0 not found")
      }
    }
    Error(e) -> io.println("❌ Failed to start: " <> e)
  }
}
