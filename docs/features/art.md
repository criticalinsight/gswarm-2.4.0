# Adaptive Radix Tree (ART) & Prefix Search

GleamDB includes a native **Adaptive Radix Tree (ART)** index to support efficient prefix search and join optimization. This index sits alongside the EAVT, AEVT, AVET, and HNSW indices to provide specialized support for string-based queries.

## The Problem

Standard B-trees or hash maps are excellent for exact matches but inefficient for prefix searches (`StartsWith`). In a logic programming context, we often need to:
1.  **Filter**: "Find all users whose name starts with 'Al'".
2.  **Generate**: "Find all values in the system that start with 'http'".

Without an index, these operations require full scans $O(N)$ or inefficient range queries.

## The Solution: ART

The **Adaptive Radix Tree** is a trie data structure that:
-   **Adapts** node sizes based on the number of children (Node4, Node16, Node48, Node256).
-   **Compresses** paths (lazy expansion) to minimize depth.
-   Provides $O(k)$ lookup time, where $k$ is the key length, independent of the number of items $N$.

## Usage: `StartsWith`

The primary interface to the ART index is the `StartsWith` clause in the query DSL.

### 1. As a Filter
When the variable is already bound by previous clauses, `StartsWith` acts as a filter.

```gleam
import gleamdb/q

// Find all users with names starting with "Al"
let query = q.new()
  |> q.where(q.v("e"), "user/name", q.v("name"))
  |> q.starts_with(q.v("name"), "Al")
  |> q.to_clauses()
```

### 2. As a Generator
When the variable is unbound, `StartsWith` uses the ART index to *generate* matching values efficiently.

```gleam
// Find ANY string value in the database starting with "http"
let query = q.new()
  |> q.starts_with(q.v("url"), "http")
  |> q.to_clauses()

// Result: [#("url", Str("https://example.com")), #("url", Str("http://google.com"))]
```

## Performance

-   **Insert/Delete**: $O(k)$ where $k$ is string length.
-   **Prefix Search**: $O(k + m)$ where $m$ is the number of results.
-   **Memory**: Highly compact due to path compression and adaptive nodes.

## Implementation Details

-   The index maps `Value -> EntityId`.
-   It is maintained automatically by the `Transactor` on every `Assert` and `Retract`.
-   It handles all `fact.Str` values. Other types are ignored by this index.
