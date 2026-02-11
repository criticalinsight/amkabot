import amkabot/store
import gleeunit
import gleeunit/should
import sqlight
import gleam/dynamic/decode

pub fn main() {
  gleeunit.main()
}

pub fn lifecycle_test() {
  // 1. Initialize in-memory DB
  let assert Ok(s) = store.init(":memory:")

  // 2. Create Schema
  let schema_sql = "
    CREATE TABLE markets (id TEXT PRIMARY KEY, slug TEXT, question TEXT, url TEXT, description TEXT, created_at INTEGER);
    CREATE TABLE prices (market_id TEXT, outcome TEXT, price REAL, timestamp INTEGER);
  "
  let _ = sqlight.exec(schema_sql, s.conn)

  // 3. Save a market
  let res = store.save_market(
    s, 
    "0x123", 
    "will-trump-win", 
    "Will Trump win?", 
    "http://polymarket.com"
  )
  should.be_ok(res)

  // 4. Save a price
  let res = store.save_price(s, "0x123", "Yes", 0.65, 1700000000)
  should.be_ok(res)

  // 5. Query it back to verify
  // We use raw sqlight query for verification since our store doesn't expose a reader yet
  let sql = "SELECT price FROM prices WHERE market_id = '0x123' LIMIT 1"
  let row_decoder = decode.list(decode.float)
  let assert Ok(rows) = sqlight.query(sql, on: s.conn, with: [], expecting: row_decoder)
  
  should.equal(rows, [[0.65]])
}
