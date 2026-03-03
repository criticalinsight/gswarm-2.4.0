import gleam/io
import gleam/int
import gleam/erlang/process
import gleam/erlang/atom
import gleamdb
import gswarm/market
import gswarm/context
import gleam/list
import gleam/float

@external(erlang, "erlang", "system_time")
fn erlang_system_time(a: atom.Atom) -> Int

pub fn start_ticker(db: gleamdb.Db, market_id: String) {
  process.spawn_unlinked(fn() {
    loop(db, market_id, 1, [], 10, 1)
  })
}

pub fn start_high_load_ticker(db: gleamdb.Db, market_id: String, batch_size: Int, interval_ms: Int) {
  process.spawn_unlinked(fn() {
    loop(db, market_id, 1, [], batch_size, interval_ms)
  })
}

fn loop(
  db: gleamdb.Db,
  market_id: String,
  count: Int,
  batch: List(market.Tick),
  batch_size: Int,
  interval_ms: Int,
) {
  // Oscillate price to trigger reflex
  let price = case count % 2 {
    0 -> 0.5
    _ -> 0.6
  }
  
  let tick = market.Tick(
    market_id: market_id,
    outcome: "Yes",
    price: price,
    volume: 100,
    timestamp: count,
    trader_id: "trader_" <> int.to_string(count % 5)
  )
  
  let new_batch = [tick, ..batch]
  
  // Transact every batch_size ticks
  let #(next_batch, latency) = case count % batch_size == 0 {
    True -> {
      // 1. Check for anomaly BEFORE ingestion 🧙🏾‍♂️
      case count % 100 == 0 {
        True -> {
          case list.first(new_batch) {
            Ok(t) -> {
             case context.detect_anomaly(db, t) {
               True -> io.println("🚨 ANOMALY DETECTED in " <> market_id <> ": Price " <> float.to_string(t.price))
               False -> Nil
             }
            }
            _ -> Nil
          }
        }
        False -> Nil
      }

      // 2. Measure Latency & Ingest
      let ms = atom.create("millisecond")
      let start_time = erlang_system_time(ms)
      
      case market.ingest_batch(db, new_batch) {
        Ok(_) -> Nil
        Error(e) -> io.println("⚠️ Batch ingest failed: " <> e)
      }
      
      let end_time = erlang_system_time(ms)
      
      case count % 100 == 0 {
        True -> io.println("⚡️ [" <> market_id <> "] Ingested " <> int.to_string(count) <> " ticks")
        False -> Nil
      }
      
      #([], end_time - start_time)
    }
    False -> #(new_batch, 0)
  }
  
  // Backpressure: If disk latency > 50ms (higher threshold for high load), slow down
  let sleep_time = case latency > 50 {
    True -> {
      io.println("⚠️ Backpressure [" <> market_id <> "]: Latency is " <> int.to_string(latency) <> "ms. Cooling down...")
      interval_ms + 100
    }
    False -> interval_ms
  }
  
  process.sleep(sleep_time)
  loop(db, market_id, count + 1, next_batch, batch_size, interval_ms)
}
