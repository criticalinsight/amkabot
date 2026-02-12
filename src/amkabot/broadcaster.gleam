import amkabot/stats
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

pub type Message {
  Update(stats.Stats)
  Subscribe(Subject(stats.Stats))
  Flush
}

pub type State {
  State(
    subscribers: List(Subject(stats.Stats)),
    buffer: Dict(String, stats.Stats),
  )
}

pub fn start() {
  start_with_timeout(1000)
}

pub fn start_with_timeout(timeout_ms: Int) {
  actor.new_with_initialiser(timeout_ms, fn(self) {
    let state = State(subscribers: [], buffer: dict.new())
    actor.initialised(state)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(loop)
  |> actor.start()
}

fn loop(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Update(s) -> {
      let new_buffer = dict.insert(state.buffer, s.trader_id, s)
      actor.continue(State(..state, buffer: new_buffer))
    }
    Subscribe(sub) -> {
      actor.continue(State(..state, subscribers: [sub, ..state.subscribers]))
    }
    Flush -> {
      // Send buffered updates to all subscribers
      let updates = dict.values(state.buffer)
      list.each(state.subscribers, fn(sub) {
        list.each(updates, fn(s) { process.send(sub, s) })
      })
      // Clear buffer
      actor.continue(State(..state, buffer: dict.new()))
    }
  }
}
