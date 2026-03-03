# Events as Facts Pattern

In GleamDB, we treat everything as a fact. This includes transient events that might typically be handled by a message queue. By recording events as persistent facts, we gain auditability, time-travel capabilities, and deterministic reactive logic.

## The Pattern

Instead of just triggering a function when something happens, you:
1. **Record** the event as a set of facts (assertions).
2. **Listen** to those assertions using GleamDB's reactive system.

### 1. Recording an Event

Use the `event.record` utility to persist an event. It automatically generates a deterministic Entity ID based on the event type and timestamp, providing idempotency.

```gleam
import gleamdb/event
import gleamdb/fact

event.record(db, "order/placed", timestamp, [
  #("order/id", fact.Int(123)),
  #("user/id", fact.Int(456))
])
```

### 2. Reacting to an Event

Use `event.on_event` to set up a listener. The callback receives the `DbState` and the `Eid` of the event entity.

```gleam
import gleamdb/event

event.on_event(db, "order/placed", fn(state, eid) {
  // Callback is triggered for every new order/placed event
  // You can pull additional data from the state using the eid
  let data = gleamdb.pull(db, eid, [gleamdb.Wildcard])
  io.println("New order received!")
})
```

## Benefits

- **Idempotency**: Retrying an event with the same timestamp will result in the same Entity ID, preventing duplicate state changes.
- **Auditability**: Every event is a fact in the database. You can query `event/type` to see the entire history of the system.
- **Time Travel**: You can query the state "as of" an event's timestamp to see exactly what the world looked like when it happened.
- **Decoupling**: The recorder of the event doesn't need to know who is listening.

## Implementation Details

- **`fact.event_uid`**: Combines `event_type` and `timestamp` into a deterministic `EntityId`.
- **Reactive System**: Uses `gleamdb.subscribe` to efficiently filter for `event/type` assertions.
- **Process Isolation**: Each listener runs in its own process, ensuring that one failing callback doesn't bring down the system.
