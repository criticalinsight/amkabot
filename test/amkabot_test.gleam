import amkabot/domain.{Buy, Redeem, TradeActivity}
import amkabot/stats
import gleam/dict
import gleam/float
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn roi_calculation_test() {
  let initial = stats.initial_state(None)

  // 1. Buy 100 USDC worth of shares
  let buy =
    TradeActivity(
      user: "trader1",
      market_title: "Test Market",
      market_slug: "test-market",
      trade_type: Buy,
      size: 100.0,
      price: 0.5,
      usdc_size: 100.0,
      timestamp: 1000,
    )

  let state1: stats.State = stats.process_activity(initial, buy)
  let _s1: stats.Stats = dict.get(state1.traders, "trader1") |> should.be_ok

  // 2. Redeem (Win) - Let's say we get 200 USDC back
  let redeem =
    TradeActivity(
      user: "trader1",
      market_title: "Test Market",
      market_slug: "test-market",
      trade_type: Redeem,
      size: 200.0,
      price: 1.0,
      usdc_size: 200.0,
      timestamp: 2000,
    )

  let state2: stats.State = stats.process_activity(state1, redeem)
  let s2: stats.Stats = dict.get(state2.traders, "trader1") |> should.be_ok
  s2.total_pnl |> should.equal(200.0)
  s2.total_invested |> should.equal(100.0)
  s2.roi |> should.equal(200.0)
}

pub fn brier_score_test() {
  let initial = stats.initial_state(None)

  // Prediction: Buy at 0.70 (probability 0.7)
  let buy =
    TradeActivity(
      user: "trader1",
      market_title: "Test",
      market_slug: "test",
      trade_type: Buy,
      size: 10.0,
      price: 0.7,
      usdc_size: 7.0,
      timestamp: 1000,
    )

  let state1: stats.State = stats.process_activity(initial, buy)

  // Resolve: Redeem
  let redeem =
    TradeActivity(
      user: "trader1",
      market_title: "Test",
      market_slug: "test",
      trade_type: Redeem,
      size: 10.0,
      price: 1.0,
      usdc_size: 10.0,
      timestamp: 2000,
    )

  let state2: stats.State = stats.process_activity(state1, redeem)
  let s: stats.Stats = dict.get(state2.traders, "trader1") |> should.be_ok

  // Brier score for p=0.7, outcome=1.0 is (0.7 - 1.0)^2 = 0.09
  float.round(s.brier_sum *. 100.0) |> should.equal(9)
  s.prediction_count |> should.equal(1)
}

pub fn calibration_test() {
  // Perfect prediction (diff 0.0) -> Calibration 1.0
  stats.calculate_calibration(0.0) |> should.equal(1.0)
  
  // Worst prediction (diff 1.0) -> Calibration 0.0
  stats.calculate_calibration(1.0) |> should.equal(0.0)
  
  // Mid prediction (diff 0.5) -> Calibration 0.5
  stats.calculate_calibration(0.5) |> should.equal(0.5)
}

pub fn sharpness_test() {
  // Max certainty (Price 1.0) -> Sharpness 0.5
  stats.calculate_sharpness(1.0) |> should.equal(0.5)
  
  // Max certainty (Price 0.0) -> Sharpness 0.5
  stats.calculate_sharpness(0.0) |> should.equal(0.5)
  
  // Max uncertainty (Price 0.5) -> Sharpness 0.0
  stats.calculate_sharpness(0.5) |> should.equal(0.0)
}

pub fn decay_test() {
  // No time passed -> Decay ~1.0
  stats.calculate_decay(0) |> should.equal(1.0)
  
  // 30 days passed -> Decay ~0.3079
  let d = stats.calculate_decay(2592000)
  // Float comparison for approximate equality
  let diff = float.absolute_value(d -. 0.3079)
  let is_close = diff <. 0.001
  is_close |> should.be_true()
}
