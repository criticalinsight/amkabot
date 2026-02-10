import gleam/json
import gleam/option.{type Option}

pub type MarketStatus {
  Open
  Resolved
}

pub type Market {
  Market(
    id: String,
    question: String,
    category: Option(String),
    status: MarketStatus,
    outcome: Option(String),
  )
}

pub type TradeType {
  Buy
  Sell
  Redeem
}

pub type TradeActivity {
  TradeActivity(
    user: String,
    market_title: String,
    market_slug: String,
    trade_type: TradeType,
    size: Float,
    price: Float,
    usdc_size: Float,
    timestamp: Int,
  )
}

pub type Trader {
  Trader(
    address: String,
    total_pnl: Float,
    total_volume: Float,
    roi: Float,
    brier_score: Float,
    prediction_count: Int,
  )
}

pub type EventType {
  MarketCreated
  MarketResolved
  TradeExecuted
}

pub type Event {
  Event(
    id: Option(Int),
    source: String,
    event_type: EventType,
    payload: json.Json,
  )
}

pub fn activity_to_json(activity: TradeActivity) -> json.Json {
  json.object([
    #("user", json.string(activity.user)),
    #("market_title", json.string(activity.market_title)),
    #("market_slug", json.string(activity.market_slug)),
    #(
      "trade_type",
      json.string(case activity.trade_type {
        Buy -> "BUY"
        Sell -> "SELL"
        Redeem -> "REDEEM"
      }),
    ),
    #("size", json.float(activity.size)),
    #("price", json.float(activity.price)),
    #("usdc_size", json.float(activity.usdc_size)),
    #("timestamp", json.int(activity.timestamp)),
  ])
}
