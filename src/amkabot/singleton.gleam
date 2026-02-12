import gleam/string
import gleam/io

@external(erlang, "amkabot_ffi", "get_pid")
pub fn get_pid() -> String

@external(erlang, "amkabot_ffi", "is_alive")
pub fn is_alive(pid: String) -> Bool

@external(erlang, "amkabot_ffi", "read_file")
fn read_file(path: String) -> Result(String, String)

@external(erlang, "amkabot_ffi", "write_file")
fn write_file_ffi(path: String, data: String) -> Result(Nil, String)

pub fn acquire_lock(path: String) -> Result(Nil, String) {
  case read_file(path) {
    Ok(pid_bin) -> {
      let pid = string.trim(pid_bin)
      case is_alive(pid) {
        True -> Error("Amkabot is already running (PID: " <> pid <> ")")
        False -> write_lock(path)
      }
    }
    Error(_) -> write_lock(path)
  }
}

fn write_lock(path: String) -> Result(Nil, String) {
  let pid = get_pid()
  case write_file_ffi(path, pid) {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to write lock file " <> path <> ": " <> err)
  }
}
