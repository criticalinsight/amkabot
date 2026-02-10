import gleam/erlang/process
import gleam/io
import gleam/string
import pog

pub fn main() {
  let db_config =
    pog.default_config(process.new_name("test_pool"))
    |> pog.host("localhost")
    |> pog.database("amkabot")
    |> pog.pool_size(1)

  let assert Ok(db_started) = pog.start(db_config)
  let db = db_started.data

  let result = pog.query("SELECT 1") |> pog.execute(db)

  case result {
    Ok(_) -> io.println("✅ Database connection successful!")
    Error(e) -> io.println("❌ Database error: " <> string.inspect(e))
  }
}
