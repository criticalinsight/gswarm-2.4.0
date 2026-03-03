import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/io
import gleamdb

pub fn start(_db: gleamdb.Db) -> Result(process.Pid, String) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(supervision.worker(fn() {
    io.println("🛡️ Supervisor: Starting Fabric subsystems...")
    // Better: Make Ticker an Actor.
    // Start a minimal actor to be the worker
    actor.new(Nil)
    |> actor.on_message(fn(_state, _msg) { actor.continue(Nil) })
    |> actor.start
  }))
  |> supervisor.start
  |> result.map(fn(started) { started.pid })
  |> result.map_error(fn(_) { "Supervisor failed to start" })
}
