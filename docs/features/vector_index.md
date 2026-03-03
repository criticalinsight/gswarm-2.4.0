# HNSW Vector Indexing ($O(\log N)$) 🧭

GleamDB includes a native **Hierarchical Navigable Small-World (HNSW)** graph index for high-performance approximate nearest neighbor (ANN) search.

## 🌟 Capabilities

- **Logarithmic Complexity**: Search performance scales as $O(\log N)$, enabling sub-millisecond queries on million-scale datasets.
- **Hierarchical Layers**: Uses a probabilistic skip-list structure to navigate large datasets efficiently.
- **Unit-Vector Normalization**: All vectors are normalized to unit length at the API boundary (`apply_datom`). This ensures that `dot_product` is mathematically equivalent to `cosine_similarity`, allowing for extreme SIMD-friendly optimization (pure multiplication/addition).
- **Beam Search**: A robust greedy search implementation maintains a "frontier" of candidates to prevent local minima traps.

## 🛠️ Usage

### 1. Ingestion
Simply assert a `fact.Vec` value. The transactor automatically normalizes and indexes it.

```gleam
import gleamdb/fact
import gleamdb

let assert Ok(_) = gleamdb.transact(db, [
  // 50-dimensional vector
  #(fact.Uid(1), "doc/embedding", fact.Vec([0.1, 0.9, ...])) 
])
```

### 2. Similarity Search
Query for the nearest neighbors using the `Similarity` predicate.

```gleam
import gleamdb/shared/types.{Similarity, Var}

let query = [
  // Find top-k nearest neighbors to the query vector with score >= 0.9
  Similarity(Var("doc"), [0.1, 0.9, ...], 0.9)
]
let results = gleamdb.query(db, query)
```

## ⚙️ Configuration

The HNSW properties (M, efConstruction, efSearch) are currently tuned for general-purpose workloads:
- **M (Max Neighbors)**: 16
- **efConstruction**: 100
- **Level Multiplier**: $1 / \ln(M)$

## ⚠️ Performance Notes
- **Normalization**: If you provide non-unit vectors, they will be normalized automatically. This consumes CPU cycles. Pre-normalize your vectors for maximum ingestion throughput.
- **Batching**: Bulk loading is significantly faster than sequential insertion due to better cache locality during graph updates.
