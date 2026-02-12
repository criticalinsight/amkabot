import amkabot/gleam_store
import gleamdb
import gleamdb/fact.{EntityId, Str, Uid}
import gleeunit
import gleeunit/should
import gleam/option.{None}

pub fn main() {
  gleeunit.main()
}

pub fn related_traders_test() {
  // Use Silicon Saturation (ETS) for tests too! 🧙🏾‍♂️
  let assert Ok(db) = gleamdb.start_named("test_db", None)
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(Uid(EntityId(1)), "bet/trader_id", Str("Alice")),
    #(Uid(EntityId(1)), "bet/market_slug", Str("market-1")),
    
    #(Uid(EntityId(2)), "bet/trader_id", Str("Bob")),
    #(Uid(EntityId(2)), "bet/market_slug", Str("market-1")),
    
    #(Uid(EntityId(3)), "bet/trader_id", Str("Charlie")),
    #(Uid(EntityId(3)), "bet/market_slug", Str("market-2")),
  ])
  
  let related = gleam_store.get_related_traders(db, "Alice")
  should.equal(related, ["Bob"])
  
  let related_bob = gleam_store.get_related_traders(db, "Bob")
  should.equal(related_bob, ["Alice"])
  
  let related_charlie = gleam_store.get_related_traders(db, "Charlie")
  should.equal(related_charlie, [])
}
