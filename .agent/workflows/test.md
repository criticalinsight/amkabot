---
description: Run the Gleam test suite and quality checks
---

# Testing Workflow (Amkabot/Gleam)

Ensure the reliability of the Prediction Market Analytics Engine through rigorous testing of pure functions, actor state, and database integrations.

## 1. Test Suite Structure

The project uses `gleeunit` for testing.

- **Location**: `test/` directory.
- **Naming Convention**: `*_test.gleam` files corresponding to `src/` modules.
- **Main Entry**: `test/amkabot_test.gleam`.

## 2. Running Tests

### Standard Test Run
Run the full test suite (Unit + Integration):
```bash
gleam test
```

### Format Check
Ensure code adheres to the official Gleam style:
```bash
gleam format --check src test
```

### Static Analysis
Run type checking without executing:
```bash
gleam check
```

## 3. Writing Tests (`gleeunit`)

### Basic Unit Test
```gleam
import gleeunit
import gleeunit/should
import amkabot/stats

pub fn brier_score_test() {
  // Metric: (Price - Outcome)^2
  // Prediction: 0.7, Outcome: 1.0 (Yes is 1.0)
  // Score: (0.7 - 1.0)^2 = 0.09
  stats.calculate_brier(0.7, 1.0)
  |> should.equal(0.09)
}
```

### Actor/State Test
```gleam
import gleeunit/should
import amkabot/stats
import amkabot/domain
import gleam/option.{None}

pub fn stats_actor_pnl_update_test() {
  let state = stats.initial_state(None)
  let activity = domain.TradeActivity(..., usdc_size: 100.0, ...)
  
  let #(new_state, _stats) = stats.process_activity_internal(state, activity)
  
  new_state.traders
  |> dict.get("0xUser")
  |> result.map(fn(s) { s.total_pnl })
  |> should.equal(Ok(100.0))
}
```

## 4. Verification Checklist

Before pushing changes:
- [ ] **Unit Tests**: Verify core math (Brier, Calibration, Sharpness).
- [ ] **Compilation**: `gleam build` passes without warnings.
- [ ] **Formatting**: `gleam format` has been run.
- [ ] **Type Safety**: No `todo` or `panic` in critical paths.
- [ ] **Resilience**: Verify UI functions without Postgres (DB-less mode).

## 6. Resilience Testing

Amkabot is designed to be **Local-First**. Verify resilience by:
1. Stopping the local Postgres service.
2. Running `gleam run`.
3. Navigating to `/leaderboard` and `/trader/:address`.
4. Ensuring PnL, Calibration, and Snapshots render without errors (PState fallback).

## 5. Continuous Integration

The CI pipeline runs:
1. `gleam deps download`
2. `gleam format --check src test`
3. `gleam test`

