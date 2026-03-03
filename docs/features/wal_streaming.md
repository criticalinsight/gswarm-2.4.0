# WAL Streaming: Real-Time Federated Pulse 📡

GleamDB Phase 15 introduces **WAL Streaming**, a reactive pub-sub mechanism for the database's Write-Ahead Log. This enables sub-millisecond push telemetry for external observers.

## Overview

Traditional Datalog queries are "Pull-based"—the application asks the database for the current state. WAL Streaming is "Push-based"—the database tells subscribers exactly what changed, as it happens.

- **Reactive**: Subscribers receive a `List(Datom)` immediately after a transaction is committed to the log.
- **De-complecting**: Separates *Detection* logic from *Query* load. External sidecars can analyze the stream without impacting database performance.
- **Efficiency**: Uses Erlang's native message passing, ensuring high throughput and low latency.

## Usage

### Subscribing to the WAL

Use the `gleamdb.subscribe_wal` API to register a process as a listener.

```gleam
import gleam/erlang/process
import gleamdb
import gleamdb/fact.{type Datom}

// 1. Create a subject to receive datoms
let self_subject = process.new_subject()

// 2. Subscribe to the transactor
gleamdb.subscribe_wal(db, self_subject)

// 3. Receive real-time updates
let assert Ok(datoms) = process.receive(self_subject, 1000)
// datoms: List(Datom)
```

### Example: High-Alpha Telemetry

In Gswarm, we use a dedicated Telemetry actor to filter the WAL for interesting signals without running complex Datalog joins on every tick.

```gleam
pub fn start_telemetry(db) {
  actor.start(Nil, fn(datoms, state) {
    list.each(datoms, fn(d) {
      case d.attribute {
        "alpha/signal" -> io.println("🚀 High Alpha Detected!")
        _ -> Nil
      }
    })
    actor.continue(state)
  })
}
```

## Performance Considerations

- **Broadcast Cost**: Sending to $N$ subscribers is $O(N)$ Erlang messages. For small numbers of subscribers (<100), this is negligible.
- **Backpressure**: Subscribers must process datoms quickly. If a subscriber's mailbox overflows, it may latency-spike the BEAM node. For high-volume producers, use an intermediate `ingest_batcher` or `buffer` actor.
- **Filtering**: Currently, subscribers receive the *entire* WAL. Future phases may introduce server-side filtering (Topic-based subscriptions).

## Relationship with Reactive Datalog

- **Reactive Datalog (`gleamdb.subscribe`)**: Pushes *Query Results* (Bindings) when they change. Useful for UIs.
- **WAL Streaming (`gleamdb.subscribe_wal`)**: Pushes *Raw Facts* (Datoms). Useful for indexing, audit logs, and signal detection sidecars.
