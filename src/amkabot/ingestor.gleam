import amkabot/domain.{activity_to_json}
import amkabot/polymarket
import amkabot/stats
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/string
import gleam/float
import gleamdb
import gleamdb/fact
import amkabot/store.{type Store}
import amkabot/gleam_store
import gleam/int

pub type Message {
  Poll
}

pub type State {
  State(
    store: Store,
    db: gleamdb.Db,
    self: process.Subject(Message),
    stats_aggregator: process.Subject(stats.Message),
  )
}

pub fn start(
  store: Store,
  db: gleamdb.Db,
  stats_aggregator: process.Subject(stats.Message),
) {
  start_with_timeout(store, db, stats_aggregator, 1000)
}

pub fn start_with_timeout(
  store: Store,
  db: gleamdb.Db,
  stats_aggregator: process.Subject(stats.Message),
  timeout_ms: Int,
) {
  actor.new_with_initialiser(timeout_ms, fn(self) {
    let state = State(store: store, db: db, self: self, stats_aggregator: stats_aggregator)
    actor.initialised(state)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(loop)
  |> actor.start()
}

fn loop(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Poll -> {
      io.println("📡 Ingestor polling leaderboards and activity...")

      case polymarket.fetch_leaderboard() {
        Ok(entries) -> {
          io.println(
            "📥 Fetched leaderboard top " <> string.inspect(list.length(entries)),
          )

          list.each(entries, fn(entry) {
            case polymarket.fetch_activity(entry.proxy_wallet) {
              Ok(activities) -> {
                io.println(
                  "✅ Found "
                  <> string.inspect(list.length(activities))
                  <> " activities for "
                  <> entry.user_name,
                )
                list.each(activities, fn(activity) {
                  // 1. Persist to Depot (DB)
                  let _ = persist_activity(state.store, state.db, activity)

                  // 2. Broadcast to PState (Stats)
                  process.send(
                    state.stats_aggregator,
                    stats.ProcessActivity(activity),
                  )
                })
              }
              Error(e) -> {
                io.println(
                  "⚠️ Activity fetch error for "
                  <> entry.proxy_wallet
                  <> ": "
                  <> string.inspect(e),
                )
              }
            }
          })
          
          // Success: Schedule next poll in 10 seconds for stress test 🧙🏾‍♂️
          io.println("🧠 Context Pulse: Searching for similar market activity...")
          let query_vec = generate_mock_embedding("Will Trump win?")
          let similar_bets = gleam_store.find_similar_bets(state.db, query_vec)
          io.println("🧠 Context: Found " <> int.to_string(list.length(similar_bets)) <> " similar bets.")
          
          process.send_after(state.self, 10_000, Poll)
        }
        Error(e) -> {
          io.println("❌ Leaderboard fetch error: " <> string.inspect(e))
          // Failure: Backoff for 30 seconds before retrying
          process.send_after(state.self, 30_000, Poll)
        }
      }
      actor.continue(state)
    }
  }
}

fn persist_activity(
  store: Store,
  db: gleamdb.Db,
  activity: domain.TradeActivity,
) {
  let payload = activity_to_json(activity) |> json.to_string

  // 1. Raw Event Log (SQLite Persistence)
  let _ = store.save_event(store, "polymarket", "trade_executed", payload)

  // 2. Structured Bet for Graph (SQLite Persistence)
  let outcome = "N/A" 
  let _ = store.save_bet(
    store,
    activity.user,
    activity.market_slug,
    outcome,
    activity.usdc_size,
    activity.price,
    activity.timestamp
  )
  
  // 3. GleamDB Graph (Information Model)
  // Use Lookup refs for declarative, idempotent upserts 🧙🏾‍♂️
  // We don't need to manually check if they exist anymore.
  
  // A. Ensure Trader exists
  let _ = gleamdb.transact_with_timeout(db, [
    #(fact.Lookup(#("trader/id", fact.Str(activity.user))), "trader/id", fact.Str(activity.user)),
  ], 5000)

  // B. Ensure Market exists
  let _ = gleamdb.transact_with_timeout(db, [
    #(fact.Lookup(#("market/slug", fact.Str(activity.market_slug))), "market/slug", fact.Str(activity.market_slug)),
  ], 5000)

  // C. Create the Bet
  let bet_id = activity.user <> "-" <> activity.market_slug <> "-" <> int.to_string(activity.timestamp)
  
  let _ = gleamdb.transact_with_timeout(db, [
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/id", fact.Str(bet_id)),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/trader_id", fact.Str(activity.user)),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/market_slug", fact.Str(activity.market_slug)),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/outcome", fact.Str(outcome)),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/amount", fact.Int(float_to_int(activity.size))),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/price", fact.Int(float_to_int(activity.price *. 10000.0))), 
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/timestamp", fact.Int(activity.timestamp)),
      #(fact.Lookup(#("bet/id", fact.Str(bet_id))), "bet/embedding", fact.Vec(generate_mock_embedding(activity.market_slug <> " " <> outcome)))
  ], 5000)
}

fn generate_mock_embedding(text: String) -> List(Float) {
  let seed = string.length(text)
  range(1, 16) 
  |> list.map(fn(i) {
    let x = int.to_float(seed + i)
    x /. 100.0
  })
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

fn float_to_int(f: Float) -> Int {
  float.truncate(f)
}
