import gleamdb/storage
import gleamdb/fact
import sqlight
import gleam/result
import gleam/dict
import gleam/list

import gleam/dynamic/decode
import gleamdb/engine
import gleamdb

pub fn get_related_traders(db: gleamdb.Db, trader_id: String) -> List(String) {
  // Query:
  // Find ?other_trader where:
  //   bet1.trader_id = $trader_id
  //   bet1.market_slug = ?slug
  //   bet2.market_slug = ?slug
  //   bet2.trader_id = ?other_trader
  //   ?other_trader != $trader_id

  let q = [
    // 1. Find markets traded by input trader
    gleamdb.p(#(engine.Var("b1"), "bet/trader_id", engine.Val(fact.Str(trader_id)))),
    gleamdb.p(#(engine.Var("b1"), "bet/market_slug", engine.Var("slug"))),
    
    // 2. Find other bets on same markets
    gleamdb.p(#(engine.Var("b2"), "bet/market_slug", engine.Var("slug"))),
    gleamdb.p(#(engine.Var("b2"), "bet/trader_id", engine.Var("other"))),
    
    // 3. Exclude self (Not implemented in Datalog engine yet? Phase 6 implemented Negation)
    // We can filter in Gleam or use Where clause if supported?
    // Engine supports "Positive" and "Negative" clauses.
    // engine.Not(#(engine.Var("other"), "Release", engine.Val...)) ??
    // We don't have inequality constraint in Datalog engine yet!
    // "Phase 6: Advanced Datalog" -> implemented Negated Clauses.
    // But we need `!=`.
    // Workaround: Filter result in Gleam.
  ]
  
  let result = gleamdb.query(db, q)
  
  // Extract "other" variable
  // engine.run returns List(Dict(String, Value))
  
  list.filter_map(result, fn(binding) {
    case dict.get(binding, "other") {
      Ok(fact.Str(t)) if t != trader_id -> Ok(t)
      _ -> Error(Nil)
    }
  })
  |> list.unique
}

pub fn adapter(conn: sqlight.Connection) -> storage.StorageAdapter {
  storage.StorageAdapter(
    init: fn() { init_schema(conn) },
    persist: fn(d) { persist_datom(conn, d) },
    recover: fn() { recover_datoms(conn) },
  )
}

fn init_schema(conn: sqlight.Connection) {
  let sql = "
    CREATE TABLE IF NOT EXISTS datoms (
      entity INTEGER,
      attribute TEXT,
      value_type TEXT,
      value_int INTEGER,
      value_str TEXT,
      tx INTEGER,
      operation TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_datoms_eavt ON datoms(entity, attribute);
  "
  let _ = sqlight.exec(sql, conn)
  Nil
}

fn persist_datom(conn: sqlight.Connection, d: fact.Datom) {
  let sql = "
    INSERT INTO datoms (entity, attribute, value_type, value_int, value_str, tx, operation)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  "
  let #(v_type, v_int, v_str) = case d.value {
    fact.Int(i) -> #("int", i, "")
    fact.Str(s) -> #("str", 0, s)
    fact.Bool(b) -> #("bool", case b { True -> 1 False -> 0 }, "")
    fact.List(_) -> #("list", 0, "TODO: serialize list") 
  }
  
  let op_str = case d.operation {
    fact.Assert -> "assert"
    fact.Retract -> "retract"
  }

  let args = [
    sqlight.int(d.entity),
    sqlight.text(d.attribute),
    sqlight.text(v_type),
    sqlight.int(v_int),
    sqlight.text(v_str),
    sqlight.int(d.tx),
    sqlight.text(op_str)
  ]
  
  let _ = sqlight.query(sql, on: conn, with: args, expecting: decode.success(Nil))
  Nil
}

fn recover_datoms(conn: sqlight.Connection) -> Result(List(fact.Datom), String) {
  let sql = "SELECT entity, attribute, value_type, value_int, value_str, tx, operation FROM datoms ORDER BY tx ASC"
  
  let decoder = {
    use entity <- decode.field(0, decode.int)
    use attribute <- decode.field(1, decode.string)
    use value_type <- decode.field(2, decode.string)
    use value_int <- decode.field(3, decode.int)
    use value_str <- decode.field(4, decode.string)
    use tx <- decode.field(5, decode.int)
    use op_str <- decode.field(6, decode.string)
    
    let value = case value_type {
      "int" -> fact.Int(value_int)
      "str" -> fact.Str(value_str)
      "bool" -> fact.Bool(value_int == 1)
      "list" -> fact.List([]) // TODO
      _ -> fact.Str("unknown")
    }
    
    let op = case op_str {
      "assert" -> fact.Assert
      "retract" -> fact.Retract
      _ -> fact.Assert
    }
    
    decode.success(fact.Datom(entity, attribute, value, tx, op))
  }
  
  sqlight.query(sql, on: conn, with: [], expecting: decoder)
  |> result.map_error(fn(e) { "Sqlight error: " <> e.message })
}
