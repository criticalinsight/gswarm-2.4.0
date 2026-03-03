import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/dict
import gleam/result
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gswarm/market

import gswarm/node.{type ShardedContext}
import gswarm/shard_manager
import gswarm/sharded_query
import gleamdb/shared/types
import gleamdb/q

const scan_interval = 60_000 // Scan every minute

// Start the Cross-Market Intelligence scanner as a standalone process
pub fn start_link(ctx: ShardedContext) -> Result(process.Pid, String) {
  let pid = process.spawn_unlinked(fn() {
    loop(ctx)
  })
  Ok(pid)
}

fn loop(ctx: ShardedContext) {
  io.println("🔍 Cross-Market: Scanning for correlations across fabric...")
  let _ = scan_correlations(ctx)
  
  process.sleep(scan_interval)
  loop(ctx)
}

// --- Correlation Logic ---

fn scan_correlations(ctx: ShardedContext) -> Result(Nil, Nil) {
  // 1. Get active markets across ALL shards
  let query = q.new()
    |> q.where(types.Var("m"), "market/id", types.Var("id"))
    |> q.to_clauses
  
  let rows = sharded_query.query_all(ctx, query)
  let markets = list.filter_map(rows.rows, fn(row) {
    case dict.get(row, "id") {
      Ok(fact.Str(id)) -> Ok(id)
      _ -> Error(Nil)
    }
  })
  
  // 2. Generate unique pairs
  let pairs = unique_pairs(markets)
  
  // 3. Analyze each pair
  list.each(pairs, fn(pair) {
    let #(id_a, id_b) = pair
    analyze_pair(ctx, id_a, id_b)
  })
  
  Ok(Nil)
}

fn analyze_pair(ctx: ShardedContext, id_a: String, id_b: String) {
  // Fetch probability series from their respective shards
  let series_a_res = case sharded_query.get_market_db(ctx, id_a) {
    Ok(db) -> market.get_probability_series(db, id_a, "YES")
    Error(_) -> Error(Nil)
  }
  let series_b_res = case sharded_query.get_market_db(ctx, id_b) {
    Ok(db) -> market.get_probability_series(db, id_b, "YES")
    Error(_) -> Error(Nil)
  }
  
  case series_a_res, series_b_res {
    Ok(series_a), Ok(series_b) -> {
      let aligned = align_series(series_a, series_b)
      case list.length(aligned) > 30 { // Need sufficient data points
        True -> {
          let correlation = calculate_pearson(aligned)
          case float.absolute_value(correlation) >. 0.7 {
            True -> {
              io.println("🔗 Strong Correlation (" <> float.to_string(correlation) <> "): " <> id_a <> " <-> " <> id_b)
              store_correlation_fact(ctx, id_a, id_b, correlation)
            }
            False -> Nil
          }
        }
        False -> Nil
      }
    }
    _, _ -> Nil
  }
}

// Align two time series by bucketing timestamps to the nearest minute
fn align_series(a: List(#(Int, Float)), b: List(#(Int, Float))) -> List(#(Float, Float)) {
  let map_a = list.fold(a, dict.new(), fn(acc, item) {
    let bucket = item.0 / 60_000
    dict.insert(acc, bucket, item.1)
  })
  
  list.filter_map(b, fn(item) {
    let bucket = item.0 / 60_000
    case dict.get(map_a, bucket) {
      Ok(val_a) -> Ok(#(val_a, item.1))
      Error(_) -> Error(Nil)
    }
  })
}

fn calculate_pearson(data: List(#(Float, Float))) -> Float {
  let n = int.to_float(list.length(data))
  
  let #(sum_x, sum_y, sum_xy, sum_x2, sum_y2) = list.fold(data, #(0.0, 0.0, 0.0, 0.0, 0.0), fn(acc, p) {
    let #(x, y) = p
    let #(sx, sy, sxy, sx2, sy2) = acc
    #(
      sx +. x,
      sy +. y,
      sxy +. x *. y,
      sx2 +. x *. x,
      sy2 +. y *. y
    )
  })
  
  let numerator = n *. sum_xy -. sum_x *. sum_y
  let den_x = float.square_root(n *. sum_x2 -. sum_x *. sum_x) |> result.unwrap(0.0)
  let den_y = float.square_root(n *. sum_y2 -. sum_y *. sum_y) |> result.unwrap(0.0)
  
  case den_x *. den_y {
    0.0 -> 0.0
    denom -> numerator /. denom
  }
}

fn unique_pairs(items: List(String)) -> List(#(String, String)) {
  case items {
    [] -> []
    [head, ..tail] -> {
      let pairs = list.map(tail, fn(x) { #(head, x) })
      list.append(pairs, unique_pairs(tail))
    }
  }
}

fn store_correlation_fact(ctx: ShardedContext, id_a: String, id_b: String, corr: Float) {
  let db = node.get_primary(ctx)
  let id_hash = shard_manager.phash2(id_a)
  let lookup = fact.Uid(fact.EntityId(id_hash))
  
  let facts = [
    #(lookup, "metric/correlation/" <> id_b, fact.Float(corr))
  ]
  
  let _ = gleamdb.transact(db, facts)
  Nil
}
