import amkabot/broadcaster
import amkabot/ingestor
import amkabot/stats
import amkabot/web
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/io
import gleam/option.{Some}
import mist
import amkabot/store
import amkabot/gleam_store
import gleamdb
import gleamdb/fact
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret_key_base =
    "an-extra-long-and-secure-secret-key-base-for-amkabot-64-bytes-long!!!"

  io.println("🚀 Initializing Amkabot - Prediction Market Tracker...")

  // Database Configuration
  let assert Ok(store) = store.init("amkabot.db")
  io.println("✅ SQLite store initialized.")
  
  // Initialize GleamDB
  let assert store.Store(conn) = store
  let adapter = gleam_store.adapter(conn)
  let db = gleamdb.new_with_adapter(Some(adapter))
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(0), "system/started_at", fact.Int(0)) // Timestamp TODO
  ])

  // Define Schema
  let assert Ok(_) = gleamdb.set_schema(db, "bet/id", fact.AttributeConfig(unique: True, component: False))
  let assert Ok(_) = gleamdb.set_schema(db, "trader/id", fact.AttributeConfig(unique: True, component: False))
  let assert Ok(_) = gleamdb.set_schema(db, "market/slug", fact.AttributeConfig(unique: True, component: False))

  io.println("✅ GleamDB initialized and connected to SQLite.")

  // Start Analytics Engine
  let assert Ok(stats_started) = stats.start(store)
  let stats_aggregator = stats_started.data
  io.println("📊 Analytics engine (PState) initialized.")

  // Start Broadcaster (Phase 8 Throttling Layer)
  let assert Ok(broadcaster_started) = broadcaster.start()
  let broadcaster_actor = broadcaster_started.data

  // Link Stats -> Broadcaster
  let stats_sub = process.new_subject()
  process.send(stats_aggregator, stats.Subscribe(stats_sub))

  // Spawn adapter to forward stats updates to broadcaster
  process.spawn(fn() {
    let selector =
      process.new_selector()
      |> process.select(stats_sub)

    // Recursive loop to forward
    forward_stats_to_broadcaster(selector, broadcaster_actor)
  })

  // Schedule periodic PState flushes (every 1 minute)
  process.spawn(fn() { periodic_flush(stats_aggregator) })

  // Schedule Broadcaster flushes (every 500ms)
  process.spawn(fn() { periodic_broadcast(broadcaster_actor) })

  // Start Ingestion Topology
  let assert Ok(ingest_started) = ingestor.start(store, db, stats_aggregator)
  process.send(ingest_started.data, ingestor.Poll)
  io.println("📡 Ingestion actor started and connected to analytics.")

  // Start Web Server with Hybrid Mist/Wisp handler
  let ctx = web.Context(stats_aggregator: stats_aggregator, store: store)

  let handler = fn(req: Request(mist.Connection)) {
    case request.path_segments(req) {
      ["ws"] -> {
        mist.websocket(
          request: req,
          on_init: fn(_conn) {
            let client_sub = process.new_subject()
            process.send(broadcaster_actor, broadcaster.Subscribe(client_sub))
            let selector =
              process.new_selector()
              |> process.select(client_sub)
            #(client_sub, Some(selector))
          },
          on_close: fn(_state) { Nil },
          handler: fn(subject, message, conn) {
            case message {
              mist.Custom(update) -> {
                let json = stats.stats_to_json(update)
                let _ = mist.send_text_frame(conn, json)
                mist.continue(subject)
              }
              mist.Text("ping") -> {
                let _ = mist.send_text_frame(conn, "pong")
                mist.continue(subject)
              }
              _ -> mist.continue(subject)
            }
          },
        )
      }
      _ -> {
        wisp_mist.handler(web.handle_request(_, ctx), secret_key_base)(req)
      }
    }
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8000)
    |> mist.start

  io.println("🕸️  Web server listening on http://localhost:8000")
  process.sleep_forever()
}

fn periodic_flush(stats_aggregator) {
  process.sleep(60_000)
  process.send(stats_aggregator, stats.Flush)
  periodic_flush(stats_aggregator)
}

fn periodic_broadcast(broadcaster_actor) {
  process.sleep(500)
  process.send(broadcaster_actor, broadcaster.Flush)
  periodic_broadcast(broadcaster_actor)
}

fn forward_stats_to_broadcaster(selector, broadcaster_actor) {
  let s = process.selector_receive_forever(selector)
  process.send(broadcaster_actor, broadcaster.Update(s))
  forward_stats_to_broadcaster(selector, broadcaster_actor)
}
