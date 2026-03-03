# Sovereign Analytics (Distributed Aggregates & Parallelism) 🧙🏾‍♂️

GleamDB v1.9.0 introduces **Sovereign Intelligence**, transforming the engine from a passive store into an active analytical substrate.

## 1. Distributed Aggregates

Query branches can now perform reduction operations in-place, avoiding the need to ship raw data to the application layer.

### Supported Operations
- `Count`: Number of matching datoms.
- `Sum`: Sum of values (Int or Float).
- `Min` / `Max`: Extremes of values (Numeric or String).
- `Avg`: Arithmetic mean.
- `Median`: Statistical median (P50).

### Distributed Coordinate Reduction (Phase 15)

In sharded environments, aggregates are resolved via a **Two-Pass Reduction**:
1.  **Partial Reduction**: Each shard computes the aggregate locally over its partition.
2.  **Global Reduction**: The coordinator merges these shard-level results. For `Sum` and `Count`, it performs a secondary `Sum` over the partial results. For `Min`/`Max`, it selects the global extreme.
This ensures correctness across distributed datasets without shipping raw facts over the network.

### Usage
Aggregates are defined in the query body using the `Aggregate` clause.

```gleam
import gleamdb/shared/types.{Aggregate, Sum}

let query = [
  // 1. Match entities and capture "age" var
  gleamdb.p(#(types.Var("e"), "age", types.Var("val"))),
  
  // 2. Aggregate "val" into "total_age" using Sum
  Aggregate("total_age", Sum, "val", []) 
]
```

## 2. Parallel Query Execution

Analytical queries often touch massive datasets. GleamDB now automatically parallelizes execution.

- **Auto-Sharding**: If an intermediate query context grows beyond **500 items**, the engine automatically shards the workload.
- **Concurrent Processing**: Shards are processed in parallel using lightweight Erlang processes (`spawn`).
- **Transparent**: No API changes required. The engine handles distribution and result collection automatically.

### Performance
For large joins or scans, parallel execution can yield **linear speedups** proportional to available CPU cores, as the overhead of process spawning is amortized over large data chunks.

## 3. Temporal Sharding (v2.2.0)

Phase 4 introduced specialized sharded read-paths for temporal range queries. By targeting specific time-slices across the sharded fabric, retrieval latency for "since" queries is minimized.

- **Speedup**: Verified **59x faster** retrieval on 10k-record datasets.
- **Native Implementation**: Integrated into `sharded.since` and `sharded_query.query_since`.
