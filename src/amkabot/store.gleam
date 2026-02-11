import gleam/dynamic/decode
import gleam/result
import sqlight
import gleam/list
import amkabot/domain

pub type Store {
  Store(conn: sqlight.Connection)
}

pub fn init(path: String) -> Result(Store, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  // Enable WAL mode on connection open
  let _ = sqlight.exec("PRAGMA journal_mode = WAL;", conn)
  Ok(Store(conn))
}

pub fn with_connection(store: Store, f: fn(sqlight.Connection) -> a) -> a {
  f(store.conn)
}

// -- Domain Helpers --

pub fn save_market(store: Store, id: String, slug: String, question: String, url: String) -> Result(Nil, sqlight.Error) {
  let sql = "
    INSERT INTO markets (id, slug, question, url) 
    VALUES (?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET 
      slug=excluded.slug, 
      question=excluded.question, 
      url=excluded.url;
  "
  let args = [
    sqlight.text(id),
    sqlight.text(slug),
    sqlight.text(question),
    sqlight.text(url)
  ]
  // helper to ignore result
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

pub fn save_price(store: Store, market_id: String, outcome: String, price: Float, timestamp: Int) -> Result(Nil, sqlight.Error) {
  let sql = "
    INSERT INTO prices (market_id, outcome, price, timestamp)
    VALUES (?, ?, ?, ?);
  "
  let args = [
    sqlight.text(market_id),
    sqlight.text(outcome),
    sqlight.float(price),
    sqlight.int(timestamp)
  ]
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

pub fn save_event(store: Store, source: String, event_type: String, payload: String) -> Result(Nil, sqlight.Error) {
  let sql = "INSERT INTO events (source, event_type, payload) VALUES (?, ?, ?)"
  let args = [sqlight.text(source), sqlight.text(event_type), sqlight.text(payload)]
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

pub fn save_bet(
  store: Store, 
  trader_id: String, 
  market_slug: String, 
  outcome: String, 
  amount: Float, 
  price: Float, 
  timestamp: Int
) -> Result(Nil, sqlight.Error) {
  let sql = "
    INSERT INTO bets (trader_id, market_slug, outcome, amount, price, timestamp)
    VALUES (?, ?, ?, ?, ?, ?)
  "
  let args = [
    sqlight.text(trader_id),
    sqlight.text(market_slug),
    sqlight.text(outcome),
    sqlight.float(amount),
    sqlight.float(price),
    sqlight.int(timestamp)
  ]
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

pub fn save_trader(
  store: Store, 
  address: String, 
  total_pnl: Float, 
  roi: Float, 
  brier_score: Float, 
  markets_count: Int
) -> Result(Nil, sqlight.Error) {
  let sql = "
    INSERT INTO traders (address, total_pnl, roi, brier_score, markets_count, last_updated_at)
    VALUES (?, ?, ?, ?, ?, unixepoch())
    ON CONFLICT(address) DO UPDATE SET
      total_pnl = excluded.total_pnl,
      roi = excluded.roi,
      brier_score = excluded.brier_score,
      markets_count = excluded.markets_count,
      last_updated_at = unixepoch()
  "
  let args = [
    sqlight.text(address), 
    sqlight.float(total_pnl), 
    sqlight.float(roi), 
    sqlight.float(brier_score), 
    sqlight.int(markets_count)
  ]
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

pub fn save_trader_snapshot(
  store: Store,
  address: String,
  cumulative_brier: Float,
  calibration_score: Float,
  sharpness_score: Float
) -> Result(Nil, sqlight.Error) {
  let sql = "
    INSERT INTO trader_snapshots (address, snapshot_date, cumulative_brier, calibration_score, sharpness_score)
    VALUES (?, date('now'), ?, ?, ?)
    ON CONFLICT(address, snapshot_date) DO UPDATE SET
      cumulative_brier = excluded.cumulative_brier,
      calibration_score = excluded.calibration_score,
      sharpness_score = excluded.sharpness_score
  "
  let args = [
    sqlight.text(address),
    sqlight.float(cumulative_brier),
    sqlight.float(calibration_score),
    sqlight.float(sharpness_score)
  ]
  let decoder = decode.success(Nil)
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
  |> result.replace(Nil)
}

// -- Graph Queries (Recursive CTE / Datalog Style) --

pub fn get_trader(store: Store, address: String) -> Result(List(domain.Trader), sqlight.Error) {
  let sql = "
    SELECT address, total_pnl, roi, brier_score, markets_count
    FROM traders
    WHERE address = ?
  " 
  let args = [sqlight.text(address)]
  
  let decoder = {
    use address <- decode.field(0, decode.string)
    use total_pnl <- decode.field(1, decode.float) 
    use roi <- decode.field(2, decode.float)
    use brier_score <- decode.field(3, decode.float)
    use markets_count <- decode.field(4, decode.int)
    decode.success(domain.Trader(
      address: address,
      total_pnl: total_pnl,
      total_volume: 0.0,
      roi: roi,
      brier_score: brier_score,
      prediction_count: markets_count
    ))
  }
  
  sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
}

pub fn get_related_traders(store: Store, address: String) -> Result(List(String), sqlight.Error) {
  // Query: Find other traders who bet on the same markets as 'address'
  // Logic: 
  // 1. Get markets traded by 'address'
  // 2. Find all OTHER traders who traded those markets
  // 3. Group by trader to get distinct list (or count for strength of connection)
  // This effectively traverses the graph: Trader A -> Market -> Trader B
  let sql = "
    WITH my_markets AS (
      SELECT DISTINCT market_slug FROM bets WHERE trader_id = ?
    )
    SELECT DISTINCT b.trader_id 
    FROM bets b
    JOIN my_markets m ON b.market_slug = m.market_slug
    WHERE b.trader_id != ?
    LIMIT 50
  "
  let args = [sqlight.text(address), sqlight.text(address)]
  let row_decoder = decode.list(decode.string)
  
  sqlight.query(sql, on: store.conn, with: args, expecting: row_decoder)
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      case list.first(row) {
        Ok(t) -> t
        Error(_) -> "" 
      }
    })
  })
}

// -- Generic Helper --
pub fn run_query(store: Store, sql: String, args: List(sqlight.Value)) -> Result(List(List(sqlight.Value)), sqlight.Error) {
   // For generic query generic return we might need a dynamic decoder
   let decoder = decode.dynamic
   sqlight.query(sql, on: store.conn, with: args, expecting: decoder)
   |> result.map(fn(_rows) { [] }) // mapping to empty because we can't easily return generic values yet
}
