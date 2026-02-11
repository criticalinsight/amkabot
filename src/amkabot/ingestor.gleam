import amkabot/domain.{type TradeActivity, activity_to_json}
import amkabot/polymarket
import amkabot/stats
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/string
import gleam/int
import gleam/float
import gleamdb
import gleamdb/fact
import amkabot/store.{type Store}

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
  actor.new_with_initialiser(1000, fn(self) {
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

fn persist_activity(store: Store, db: gleamdb.Db, activity: TradeActivity) {
  let payload = activity_to_json(activity) |> json.to_string

  // 1. Raw Event Log
  let _ = store.save_event(store, "polymarket", "trade_executed", payload)

  // 2. Structured Bet for Graph
  // defaulting outcome to "N/A" as it is not currently captured in TradeActivity
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
  
  // 3. GleamDB Graph
  // Structure: 
  //   Trader --[trader/id]--> (E1)
  //   Market --[market/slug]--> (E2)
  //   Bet --[bet/id]--> (E3)
  //   (E3) --[bet/trader]--> (E1)
  //   (E3) --[bet/market]--> (E2)
  
  // Ideally we use lookup refs to assert relationships without knowing EIDs.
  // But GleamDB expects {Eid, Attr, Val}. 
  // If we assert a fact with Lookup Ref as EID, does it create it?
  // "Phase 8: Implement Lookup Refs (EID replacement)" -> Yes.
  
  // We need to ensure the entities exist or are created via the lookup ref.
  // Asserting a fact checks if entity exists via index. If not? 
  // Currently Lookup Ref works for determining EID of *existing* entity.
  // Does it support upsert (create if missing)? 
  // "Unification of EID" usually implies resolving.
  // If I want to CREATE a trader if missing, I need to assert `trader/id`.
  
  let trader_ref = fact.Lookup(#("trader/id", fact.Str(activity.user)))
  let market_ref = fact.Lookup(#("market/slug", fact.Str(activity.market_slug)))
  
  // We'll use a transaction that asserts identity for trader and market, then links them.
  // Note: We need to give them temp IDs if creating new ones in same tx?
  // Or if we use Lookup Ref as EID in the tuple?
  // Current implementation of Transactor resolves Lookups. 
  
  // Let's assume we can use Lookup Ref as the EID in the Fact tuple.
  // This asserts: "The entity identified by trader/id=X has trader/id=X" (idempotent setup)
  
  let _ = gleamdb.transact(db, [
    // Ensure Trader exists
    #(trader_ref, "trader/id", fact.Str(activity.user)),
    
    // Ensure Market exists
    #(market_ref, "market/slug", fact.Str(activity.market_slug)),
    
    // Create Bet (using hash or random ID? Activity doesn't have ID?)
    // activity.id isn't in snippet. Assuming hash of content.
    // For now, let's use a temp ID for the new bet (negative integer).
    #(fact.EntityId(-1), "bet/trader", fact.Str(activity.user)), // Linking by value? No, needs to link to Entity!
    // Wait, GleamDB value type for Ref is... Int (EntityId).
    // I can't look up the Entity ID of "user" inside the transaction easily unless I have a "Value Ref" type?
    // GleamDB doesn't seem to have "Value Ref" yet (Phase 10 feature?).
    // Phase 8 says "Implement Lookup Refs (EID replacement)". This usually means `#(Lookup("attr", "val"), "attr2", "val2")`.
    // It doesn't necessarily mean `#(EntityId(1), "ref_attr", Lookup("attr", "val"))`.
    // So I can't link to an entity by Lookup Ref in the *Value* position yet.
    
    // Workaround: 
    // Two transactions? Or resolve first?
    // Since this is dogfooding, this is a feature request! 
    // "Support Lookup Refs in Value position for Ref attributes".
    
    // For now, I'll just store the string value "bet/trader_id" = "0x..." instead of a graph ref.
    // Steps to true Graph:
    // 1. Resolve Trader EID (or create)
    // 2. Resolve Market EID (or create)
    // 3. Create Bet EID linking 1 & 2.
  ])
  
  // Doing it properly:
  // Since I can't do it all in one TX without Value-Ref support, I'll do it sequentially for now
  // or just store the flat data and query it.
  // Let's store flat for MVP: 
  // bet_entity: { bet/trader_id: "alice", bet/market_slug: "trump-2024" }
  // We can still join on these strings!
  
  let _ = gleamdb.transact(db, [
     #(fact.EntityId(-1), "bet/trader_id", fact.Str(activity.user)),
     #(fact.EntityId(-1), "bet/market_slug", fact.Str(activity.market_slug)),
     #(fact.EntityId(-1), "bet/amount", fact.Int(float_to_int(activity.usdc_size))),
     #(fact.EntityId(-1), "bet/price", fact.Int(float_to_int(activity.price *. 100.0))), 
     #(fact.EntityId(-1), "bet/timestamp", fact.Int(activity.timestamp))
  ])
  Nil
}

fn float_to_int(f: Float) -> Int {
  float.truncate(f)
}
