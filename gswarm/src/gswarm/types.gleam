
pub type Event {
  InsiderAlert(market: String, trader: String, score: Float, action: String, price: Float, is_first: Bool)
  FirstMover(market: String, cluster_size: Int, source: String)
  TradeExecuted(action: String, market: String, source: String, roi: Float, balance: Float)
  TradeGated(market: String, reason: String)
  SystemHealth(component: String, message: String)
  ScoutSignal(kind: String, source: String, value: Float)
}

pub type TargetingPolicy {
  TargetingPolicy(
    min_roi: Float,
    min_invested: Float,
    target_price_min: Float,
    target_price_max: Float,
    exclude_legacy_traders: Bool
  )
}
