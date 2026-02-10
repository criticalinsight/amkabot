import amkabot/domain.{type TradeActivity, activity_to_json}
import amkabot/polymarket
import amkabot/stats
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/string
import pog

pub type Message {
  Poll
}

pub type State {
  State(
    db: pog.Connection,
    self: process.Subject(Message),
    stats_aggregator: process.Subject(stats.Message),
  )
}

pub fn start(
  db: pog.Connection,
  stats_aggregator: process.Subject(stats.Message),
) {
  actor.new_with_initialiser(1000, fn(self) {
    let state = State(db: db, self: self, stats_aggregator: stats_aggregator)
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
                  let _ = persist_activity(state.db, activity)

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
        }
        Error(e) -> {
          io.println("❌ Leaderboard fetch error: " <> string.inspect(e))
        }
      }

      // Schedule next poll in 5 minutes
      process.send_after(state.self, 300_000, Poll)
      actor.continue(state)
    }
  }
}

fn persist_activity(db: pog.Connection, activity: TradeActivity) {
  let payload = activity_to_json(activity) |> json.to_string

  // We use a simple hash of activity metadata as a weak idempotency key in the payload or just insert
  // For now, we trust the fetch interval or we could check for existence.
  // Let's refine the schema later if duplicates become a problem.
  let sql =
    "
    INSERT INTO events (source, event_type, payload)
    VALUES ($1, $2, $3)
  "
  let _ =
    pog.query(sql)
    |> pog.parameter(pog.text("polymarket"))
    |> pog.parameter(pog.text("trade_executed"))
    |> pog.parameter(pog.text(payload))
    |> pog.execute(db)
}
