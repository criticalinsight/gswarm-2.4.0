import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/list
import gswarm/amka_domain.{type TradeActivity}

// Strategy Configuration
pub type StrategyConfig {
  StrategyConfig(
    categories: List(String),
    min_price: Float,
    max_price: Float,
    whale_invested_threshold: Float,
    whale_roi_threshold: Float,
    min_trades_for_non_whale: Int
  )
}

pub const default_config = StrategyConfig(
  categories: ["politic", "us-current-affairs", "world"],
  min_price: 0.2,
  max_price: 0.4,
  whale_invested_threshold: 10000.0,
  whale_roi_threshold: 20.0,
  min_trades_for_non_whale: 30
)

pub type SignalType {
  WhaleSighting(user: String, roi: Float, invested: Float)
  TargetPriceHit(market: String, price: Float)
}

/// Gatekeeper: Should we even ingest this market?
pub fn should_track_market(category: String) -> Bool {
  let cat = string.lowercase(category)
  list.any(default_config.categories, fn(c) { string.contains(cat, c) })
}

/// Analyst: Is this specific trade interesting?
pub fn analyze_activity(
  activity: TradeActivity, 
  total_invested: Float, 
  roi: Float, 
  trade_count: Int
) -> Option(SignalType) {
  let is_whale = total_invested >. default_config.whale_invested_threshold || roi >. default_config.whale_roi_threshold
  let is_target_price = activity.price >=. default_config.min_price && activity.price <=. default_config.max_price
  let _is_established = trade_count > default_config.min_trades_for_non_whale

  case is_whale {
    True -> Some(WhaleSighting(activity.user, roi, total_invested))
    False -> {
      case is_target_price {
        True -> Some(TargetPriceHit(activity.market_slug, activity.price))
        False -> None
      }
    }
  }
}

/// Filter: Should we keep this trader in our memory?
pub fn should_keep_trader(total_invested: Float, roi: Float, trade_count: Int) -> Bool {
  let is_whale = total_invested >. default_config.whale_invested_threshold || roi >. default_config.whale_roi_threshold
  let is_established = trade_count > default_config.min_trades_for_non_whale
  
  is_whale || !is_established // Keep whales AND new traders (<= 30 trades)
}
