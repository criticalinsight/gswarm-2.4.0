# Time Travel (Diff)

GleamDB is a time-traveling database. Every fact is associated with a transaction ID (`tx`), allowing for deep introspection of historical changes.

## The Diff Capability
The `gleamdb.diff` function allows you to retrieve the exact set of datoms (assertions and retractions) that occurred between any two points in history.

## Usage

### Comparing Transactions
Retrieve all changes that occurred from `tx_start` (exclusive) to `tx_end` (inclusive).

```gleam
import gleamdb

// What happened between T1 and T3?
let changes = gleamdb.diff(db, tx1, tx3)

// 'changes' is a List(fact.Datom)
// Each datom contains:
// - entity: EntityId
// - attr: String
// - value: Value
// - tx: Int
// - operation: Assert | Retract
```

## Implementation Details
- **Index Scan**: `diff` scans the `EAVT` (Entity-Attribute-Value-Transaction) index within the specified transaction range.
- **Performance**: While powerful, wide transaction ranges can be heavy on large datasets. It is recommended to use `diff` for focused audit logs or synchronization deltas.
- **Cardinality Aware**: If an attribute is marked as `Cardinality.One`, replacing a value will result in two datoms in the diff: a `Retract` for the old value and an `Assert` for the new one.

## Use Cases
1.  **Audit Logs**: Exactly identify who changed what and when.
2.  **Sync Engines**: Calculate the delta needed to update a remote state.
3.  **Debugging**: Trace the lifecycle of an entity through time.
