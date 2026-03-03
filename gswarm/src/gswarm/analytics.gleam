import gleam/float
import gleam/int
import gleam/list
import gleam/result

pub fn calculate_all_metrics(
  price_history: List(Float),
  volume_history: List(Int),
) -> List(Float) {
  let sma10 = sma(price_history, 10)
  let sma20 = sma(price_history, 20)
  let sma50 = sma(price_history, 50)
  let sma200 = sma(price_history, 200)
  
  let ema12 = ema(price_history, 12)
  let ema26 = ema(price_history, 26)
  
  let rsi_val = rsi(price_history, 14)
  let macd_val = ema12 -. ema26
  
  let #(bb_upper, bb_lower) = bollinger_bands(price_history, 20)
  let atr_val = atr(price_history, 14)
  
  // Volume Intelligence (Phase 31)
  let vol_sma10 = volume_sma(volume_history, 10)
  let obv_val = obv(price_history, volume_history)
  let vwap_val = vwap(price_history, volume_history)
  
  // Temporal Features (Phase 33) — filled by caller via timestamp
  // Slots 14-16 reserved for: hour_norm, weekday_norm, seconds_since_midnight_norm
  // Caller passes these in separately; here we pad with 0.0 as default
  
  let base_metrics = [
    sma10, sma20, sma50, sma200,       // 0-3: Trend
    ema12, ema26,                        // 4-5: Exponential Trend
    rsi_val,                             // 6: Momentum
    macd_val,                            // 7: Momentum
    bb_upper, bb_lower,                  // 8-9: Volatility
    atr_val,                             // 10: Volatility
    vol_sma10,                           // 11: Volume
    obv_val,                             // 12: Volume (OBV)
    vwap_val,                            // 13: Volume (VWAP)
    // 14-16: Temporal (filled by caller)
  ]
  
  let padding_needed = 50 - list.length(base_metrics)
  let padding = list.repeat(0.0, padding_needed)
  
  list.append(base_metrics, padding)
}

/// Calculate metrics WITH temporal features injected at indices 14-16
pub fn calculate_all_metrics_with_time(
  price_history: List(Float),
  volume_history: List(Int),
  timestamp: Int,
) -> List(Float) {
  let base = calculate_all_metrics(price_history, volume_history)
  let temporal = temporal_features(timestamp)
  
  // Replace indices 14, 15, 16 with temporal values
  inject_temporal(base, temporal, 0, 14)
}

// --- Trend Metrics ---

pub fn sma(history: List(Float), period: Int) -> Float {
  let period_data = list.take(history, period)
  let count = list.length(period_data)
  case count == 0 {
    True -> 0.0
    False -> list.fold(period_data, 0.0, float.add) /. int.to_float(count)
  }
}

pub fn ema(history: List(Float), period: Int) -> Float {
  let alpha = 2.0 /. int.to_float(period + 1)
  case list.reverse(history) {
    [] -> 0.0
    [first, ..rest] -> {
      list.fold(rest, first, fn(previous_ema, current_price) {
        alpha *. current_price +. {1.0 -. alpha} *. previous_ema
      })
    }
  }
}

// --- Momentum Metrics ---

pub fn rsi(history: List(Float), period: Int) -> Float {
  let diffs = get_diffs(history)
  let period_diffs = list.take(diffs, period)
  
  let gains = list.filter(period_diffs, fn(d) { d >. 0.0 })
  let losses = list.filter(period_diffs, fn(d) { d <. 0.0 }) |> list.map(float.negate)
  
  let avg_gain = sma(gains, period)
  let avg_loss = sma(losses, period)
  
  case avg_loss == 0.0 {
    True -> 100.0
    False -> {
      let rs = avg_gain /. avg_loss
      100.0 -. {100.0 /. {1.0 +. rs}}
    }
  }
}

// --- Volume Metrics ---

pub fn volume_sma(history: List(Int), period: Int) -> Float {
  let period_data = list.take(history, period)
  let count = list.length(period_data)
  case count == 0 {
    True -> 0.0
    False -> {
      let sum = list.fold(period_data, 0, int.add)
      int.to_float(sum) /. int.to_float(count)
    }
  }
}

// --- Volatility Metrics ---

pub fn bollinger_bands(history: List(Float), period: Int) -> #(Float, Float) {
  let period_data = list.take(history, period)
  let mid = sma(period_data, period)
  let dev = std_dev(period_data)
  #(mid +. 2.0 *. dev, mid -. 2.0 *. dev)
}

pub fn std_dev(data: List(Float)) -> Float {
  let len = int.to_float(list.length(data))
  case len == 0.0 {
    True -> 0.0
    False -> {
      let mean = list.fold(data, 0.0, float.add) /. len
      let variance = list.fold(data, 0.0, fn(acc, val) {
        let diff = val -. mean
        acc +. result.unwrap(float.power(diff, 2.0), 0.0)
      }) /. len
      result.unwrap(float.square_root(variance), 0.0)
    }
  }
}

pub fn atr(history: List(Float), period: Int) -> Float {
  case history {
    [] -> 0.0
    [_] -> 0.0
    _ -> {
      let ranges = get_ranges(history)
      sma(ranges, period)
    }
  }
}

// --- Volume Intelligence (Phase 31) ---

/// On-Balance Volume: cumulative volume that flows with price direction.
pub fn obv(prices: List(Float), volumes: List(Int)) -> Float {
  case prices, volumes {
    [], _ | [_], _ | _, [] | _, [_] -> 0.0
    [curr, prev, ..p_rest], [vol, ..v_rest] -> {
      let direction = case curr >. prev {
        True -> 1.0
        False -> case curr <. prev {
          True -> -1.0
          False -> 0.0
        }
      }
      let res = direction *. int.to_float(vol) +. obv([prev, ..p_rest], v_rest)
      // io.println("DEBUG: obv=" <> float.to_string(res))
      res
    }
  }
}

/// Volume-Weighted Average Price: sum(price*volume) / sum(volume)
pub fn vwap(prices: List(Float), volumes: List(Int)) -> Float {
  let pairs = list.zip(prices, volumes)
  let #(pv_sum, v_sum) = list.fold(pairs, #(0.0, 0), fn(acc, pair) {
    let #(price, vol) = pair
    #(acc.0 +. price *. int.to_float(vol), acc.1 + vol)
  })
  case v_sum > 0 {
    True -> pv_sum /. int.to_float(v_sum)
    False -> 0.0
  }
}

// --- Temporal Features (Phase 33) ---

/// Extract time-of-day features from a millisecond timestamp.
/// Returns [hour_norm, weekday_norm, seconds_since_midnight_norm]
pub fn temporal_features(timestamp_ms: Int) -> List(Float) {
  // Convert ms to seconds
  let ts_sec = timestamp_ms / 1000
  // Seconds in a day
  let seconds_in_day = 86_400
  let seconds_since_midnight = ts_sec % seconds_in_day
  let hour = seconds_since_midnight / 3600
  
  // Day of week: Unix epoch (1970-01-01) was a Thursday (day 4)
  let day_since_epoch = ts_sec / seconds_in_day
  let weekday = { day_since_epoch + 4 } % 7  // 0=Sun, 6=Sat
  
  let hour_norm = int.to_float(hour) /. 23.0
  let weekday_norm = int.to_float(weekday) /. 6.0
  let midnight_norm = int.to_float(seconds_since_midnight) /. int.to_float(seconds_in_day)
  
  [hour_norm, weekday_norm, midnight_norm]
}

// --- Helpers ---

fn get_ranges(history: List(Float)) -> List(Float) {
  case history {
    [] | [_] -> []
    [curr, prev, ..rest] -> [
      float.max(curr, prev) -. float.min(curr, prev),
      ..get_ranges([prev, ..rest])
    ]
  }
}

fn get_diffs(history: List(Float)) -> List(Float) {
  case history {
    [] | [_] -> []
    [curr, prev, ..rest] -> {
      let diff = curr -. prev
      // io.println("DEBUG: diff=" <> float.to_string(diff))
      [diff, ..get_diffs([prev, ..rest])]
    }
  }
}

/// Inject temporal values at specific indices in a vector
fn inject_temporal(
  vec: List(Float),
  temporal: List(Float),
  current_idx: Int,
  target_idx: Int
) -> List(Float) {
  case vec, temporal {
    [], _ -> []
    [head, ..rest], _ if current_idx < target_idx ->
      [head, ..inject_temporal(rest, temporal, current_idx + 1, target_idx)]
    [_head, ..rest], [t, ..t_rest] ->
      [t, ..inject_temporal(rest, t_rest, current_idx + 1, target_idx + 1)]
    [head, ..rest], [] ->
      [head, ..inject_temporal(rest, [], current_idx + 1, target_idx)]
  }
}
