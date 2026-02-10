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
  actor.new(State(subscribers: [], buffer: dict.new()))
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
