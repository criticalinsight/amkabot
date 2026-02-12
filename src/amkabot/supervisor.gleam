import amkabot/broadcaster
import amkabot/stats
import amkabot/store.{type Store}
import gleam/otp/static_supervisor
import gleam/otp/supervision

pub type Context {
  Context(
    store: Store,
  )
}

pub fn start(ctx: Context) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(
    supervision.worker(fn() { stats.start(ctx.store) })
  )
  |> static_supervisor.add(
    supervision.worker(fn() { broadcaster.start() })
  )
  |> static_supervisor.start()
}
