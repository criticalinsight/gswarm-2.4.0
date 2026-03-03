import gleam/int
import gleam/float

/// Brier Score measures the accuracy of probabilistic predictions.
/// Lower is better (0.0 = perfect, 1.0 = total error).
/// 
/// Score = (Probability - ActualOutcome)^2
/// ActualOutcome: 1.0 for YES, 0.0 for NO.
pub fn calculate_brier_score(probability: Float, actual_outcome: Float) -> Float {
  let diff = probability -. actual_outcome
  diff *. diff
}

/// A compound score representing the "Competence" of a trader.
/// Competence = Alpha (Phase 5) * Calibration (1 - AvgBrier) * Scale (sqrt(N))
pub fn calculate_competence_index(
  alpha_score: Float,
  avg_brier: Float,
  trade_count: Int
) -> Float {
  // Calibration: 1.0 is perfect, 0.0 is random noise
  let calibration = 1.0 -. avg_brier
  
  // Use sqrt of count to reward consistency over luck without making it linear
  let scale = case trade_count {
    c if c > 0 -> {
      case float.square_root(int.to_float(c)) {
        Ok(s) -> s
        _ -> 1.0
      }
    }
    _ -> 0.0
  }
  
  alpha_score *. calibration *. scale
}
