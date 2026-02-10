---
description: Guide for refactoring Gleam code to be idiomatic and simple
---

# Refactoring Workflow (Amkabot/Gleam)

"Simplicity is prerequisite for reliability." — Edsger W. Dijkstra (and Rich Hickey)

This workflow guides the refactoring process to ensure Amkabot remains **Simple** (unentangled) rather than just **Easy** (familiar).

## 1. Principles of Gleam Refactoring

### 1.1 Functional Core, Imperative Shell
- **The Core**: Pure functions in `domain.gleam`, `stats.gleam` (calculations). No `io`, no `process`, no side effects.
- **The Shell**: Actors (`ingestor`, `broadcaster`) and Web Handlers. These manage state and side effects.
- **Goal**: Move logic *out* of actors and into pure functions that can be tested in isolation.

### 1.2 Type-Driven Design
- **Make Illegal States Unrepresentable**: Use custom types and `Result` to enforce validity at compile time.

### 1.4 Resilience & State Mirroring
- **Mirroring**: Any data required for the visual UI (snapshots, activity feeds) should be mirrored in the Actor's in-memory PState.
- **DB as Side Effect**: Database writes should be side-effects of the actor loop. The system must remain operational if the DB write fails.
- **Seeding**: New entities should have synthetic history seeded to ensure immediate visual fidelity in the UI.

### 1.3 Pipeline Clarity (`|>`)
- Refactor deeply nested function calls into linear pipelines.
- **Rule**: If a pipeline exceeds 5 steps or becomes hard to name, break it into a named helper function.

## 2. Refactoring Checklist

#### [ ] Decomplecting
- Does this function do **one thing**?
- Are we passing the entire `State` when we only need a `Stats` record?
- *Action*: Narrow argument types to the smallest required data.

#### [ ] Naming
- Do names reflect **what** the data is, not **how** it is stored?
  - *Bad*: `user_dict`
  - *Good*: `traders`
- Do function names describe the transformation?
  - *Bad*: `handle_data`
  - *Good*: `calculate_calibration`

#### [ ] Safety
- Are we using `let assert` in production code?
- *Action*: Replace `let assert` with `case` handling or `result.unwrap` where appropriate, unless crashing is the correct behavior (Erlang philosophy).

## 3. Common Refactoring Patterns

### Extracting Logic from Actors
**Before:**
```gleam
// Inside actor loop
let new_score = old_score + 1.0
let new_count = count + 1
let avg = new_score /. int.to_float(new_count)
actor.continue(State(.., score: new_score, count: new_count))
```

**After:**
```gleam
// In pure helper or module
fn update_stats(stats: Stats) -> Stats {
  let new_score = stats.score + 1.0
  let new_count = stats.count + 1
  Stats(..stats, score: new_score, count: new_count)
}

// Inside actor loop
let new_stats = update_stats(current_stats)
actor.continue(State(.., stats: new_stats))
```

### Result Monad Pipelines
**Before:**
```gleam
case step1(input) {
  Ok(a) -> case step2(a) {
    Ok(b) -> step3(b)
    Error(e) -> Error(e)
  }
  Error(e) -> Error(e)
}
```

**After:**
```gleam
use a <- result.try(step1(input))
use b <- result.try(step2(a))
step3(b)
```

## 4. Execution
1.  **verify**: Run `gleam test` to ensure green state.
2.  **refactor**: Apply changes.
3.  **format**: Run `gleam format` to standardize layout.
4.  **test**: Run `gleam test` again.
