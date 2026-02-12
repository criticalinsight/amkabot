import gleamdb/storage
import gleamdb/fact
import sqlight
import gleam/result
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/dynamic/decode
import gleam/string
import gleam/float
import gleamdb/shared/types as db_types
import gleamdb

pub fn get_related_traders(db: gleamdb.Db, trader_id: String) -> List(String) {
  let q = [
    gleamdb.p(#(db_types.Var("b1"), "bet/trader_id", db_types.Val(fact.Str(trader_id)))),
    gleamdb.p(#(db_types.Var("b1"), "bet/market_slug", db_types.Var("slug"))),
    gleamdb.p(#(db_types.Var("b2"), "bet/market_slug", db_types.Var("slug"))),
    gleamdb.p(#(db_types.Var("b2"), "bet/trader_id", db_types.Var("other"))),
  ]
  
  let result = gleamdb.query(db, q)
  
  list.filter_map(result, fn(binding) {
    case dict.get(binding, "other") {
      Ok(fact.Str(t)) if t != trader_id -> Ok(t)
      _ -> Error(Nil)
    }
  })
  |> list.unique
}

pub fn find_similar_bets(db: gleamdb.Db, query_vec: List(Float)) -> List(String) {
  let q = [
     db_types.Similarity("sim_vec", query_vec, 0.7),
     db_types.Positive(#(db_types.Var("bet"), "bet/embedding", db_types.Var("sim_vec"))),
     db_types.Positive(#(db_types.Var("bet"), "bet/id", db_types.Var("bid")))
  ]
  
  let result = gleamdb.query(db, q)
  
  list.filter_map(result, fn(binding) {
    case dict.get(binding, "bid") {
      Ok(fact.Str(id)) -> Ok(id)
      _ -> Error(Nil)
    }
  })
}

pub fn adapter(conn: sqlight.Connection) -> storage.StorageAdapter {
  storage.StorageAdapter(
    init: fn() { init_schema(conn) },
    persist: fn(d) { persist_datom(conn, d) },
    persist_batch: fn(ds) { persist_batch(conn, ds) },
    recover: fn() { recover_datoms(conn) },
  )
}

fn init_schema(conn: sqlight.Connection) {
  let assert Ok(_) = sqlight.exec("PRAGMA journal_mode=WAL;", conn)
  
  let sql = "
    CREATE TABLE IF NOT EXISTS datoms (
      entity INTEGER,
      attribute TEXT,
      value_type TEXT,
      value_int INTEGER,
      value_float REAL,
      value_str TEXT,
      tx INTEGER,
      operation TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_datoms_eavt ON datoms(entity, attribute);
  "
  let _ = sqlight.exec(sql, conn)
  // Migration: add value_float if it doesn't exist
  let _ = sqlight.exec("ALTER TABLE datoms ADD COLUMN value_float REAL DEFAULT 0.0;", conn)
  Nil
}

fn persist_datom(conn: sqlight.Connection, d: fact.Datom) {
  let sql = "
    INSERT INTO datoms (entity, attribute, value_type, value_int, value_float, value_str, tx, operation)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  "
  let #(v_type, v_int, v_float, v_str) = case d.value {
    fact.Int(i) -> #("int", i, 0.0, "")
    fact.Str(s) -> #("str", 0, 0.0, s)
    fact.Float(f) -> #("float", 0, f, "")
    fact.Bool(b) -> #("bool", case b { True -> 1 False -> 0 }, 0.0, "")
    fact.Ref(fact.EntityId(id)) -> #("ref", id, 0.0, "")
    fact.List(_) -> #("list", 0, 0.0, "TODO: serialize list")
    fact.Vec(v) -> #("vec", 0, 0.0, string.join(list.map(v, float.to_string), ","))
  }
  
  let op_str = case d.operation {
    fact.Assert -> "assert"
    fact.Retract -> "retract"
  }

  let fact.EntityId(eid_int) = d.entity

  let args = [
    sqlight.int(eid_int),
    sqlight.text(d.attribute),
    sqlight.text(v_type),
    sqlight.int(v_int),
    sqlight.float(v_float),
    sqlight.text(v_str),
    sqlight.int(d.tx),
    sqlight.text(op_str)
  ]
  
  let _ = sqlight.query(sql, on: conn, with: args, expecting: decode.success(Nil))
  Nil
}

fn persist_batch(conn: sqlight.Connection, datoms: List(fact.Datom)) {
  let assert Ok(_) = sqlight.exec("BEGIN", conn)
  list.each(datoms, fn(d) { persist_datom(conn, d) })
  let assert Ok(_) = sqlight.exec("COMMIT", conn)
  Nil
}

fn recover_datoms(conn: sqlight.Connection) -> Result(List(fact.Datom), String) {
  let sql = "SELECT entity, attribute, value_type, value_int, value_float, value_str, tx, operation FROM datoms ORDER BY tx ASC"
  
  let decoder = {
    use entity_int <- decode.field(0, decode.int)
    use attribute <- decode.field(1, decode.string)
    use value_type <- decode.field(2, decode.string)
    use value_int <- decode.field(3, decode.int)
    use value_float <- decode.field(4, decode.float)
    use value_str <- decode.field(5, decode.string)
    use tx <- decode.field(6, decode.int)
    use op_str <- decode.field(7, decode.string)
    
    let value = case value_type {
      "int" -> fact.Int(value_int)
      "str" -> fact.Str(value_str)
      "float" -> fact.Float(value_float)
      "bool" -> fact.Bool(value_int == 1)
      "ref" -> fact.Ref(fact.EntityId(value_int))
      "list" -> fact.List([])
      "vec" -> {
        let nums = string.split(value_str, ",")
        let floats = list.filter_map(nums, float.parse)
        fact.Vec(floats)
      }
      _ -> fact.Str("unknown")
    }
    
    let op = case op_str {
      "assert" -> fact.Assert
      "retract" -> fact.Retract
      _ -> fact.Assert
    }
    
    decode.success(fact.Datom(fact.EntityId(entity_int), attribute, value, tx, op))
  }
  
  sqlight.query(sql, on: conn, with: [], expecting: decoder)
  |> result.map_error(fn(e) { "Sqlight error: " <> e.message })
}

pub fn load_all_datoms(conn: sqlight.Connection) -> Result(List(fact.Datom), String) {
  recover_datoms(conn)
}
