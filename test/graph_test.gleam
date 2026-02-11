import amkabot/gleam_store
import gleamdb
import gleamdb/fact
import gleeunit
import gleeunit/should
import gleam/option.{None}

pub fn main() {
  gleeunit.main()
}

pub fn related_traders_test() {
  // 1. Setup in-memory DB (None iterator -> default Mnesia mock/noop)
  // Wait, I need an adapter? new_with_adapter(None) uses Mnesia mock.
  // Mnesia mock recover returns empty list.
  let db = gleamdb.new()
  
  // 2. Transact Bets
  // Alice bets on "market-1"
  // Bob bets on "market-1"
  // Charlie bets on "market-2"
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "bet/trader_id", fact.Str("Alice")),
    #(fact.EntityId(1), "bet/market_slug", fact.Str("market-1")),
    
    #(fact.EntityId(2), "bet/trader_id", fact.Str("Bob")),
    #(fact.EntityId(2), "bet/market_slug", fact.Str("market-1")),
    
    #(fact.EntityId(3), "bet/trader_id", fact.Str("Charlie")),
    #(fact.EntityId(3), "bet/market_slug", fact.Str("market-2")),
  ])
  
  // 3. Query related to Alice
  let related = gleam_store.get_related_traders(db, "Alice")
  
  // 4. Expect Bob (shared market-1), but not Charlie
  should.equal(related, ["Bob"])
  
  // 5. Query related to Bob -> Alice
  let related_bob = gleam_store.get_related_traders(db, "Bob")
  should.equal(related_bob, ["Alice"])
  
  // 6. Query related to Charlie -> Empty
  let related_charlie = gleam_store.get_related_traders(db, "Charlie")
  should.equal(related_charlie, [])
}
