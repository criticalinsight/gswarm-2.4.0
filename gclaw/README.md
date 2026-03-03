# GClaw 🧙🏾‍♂️

> "Memory is the fabric of intelligence."

GClaw is the autonomous agentic memory layer for the Gswarm monorepo. It implements a **Tiered Hybrid Search** architecture, combining the precision of keyword-based retrieval (BM25) with the depth of semantic vectors.

## 🚀 Key Capabilities
- **Hybrid Memory**: Unified retrieval combining Recent Context (Temporal), Keyword Search (BM25), and Semantic Search (Vector).
- **Tiered Architecture**:
    - **Tier 1 (GleamDB Core)**: Native BM25 and Score Combiners.
    - **Tier 2 (Extension Registry)**: Custom index adapters for metrics like *Importance* and *Sentiment*.
    - **Tier 3 (Application Layer)**: Memory policies, auto-provider selection, and markdown export.
- **Silicon Persistence**: Durable disk-backed memory using a high-fidelity binary `Datom` format.

## 🏁 Performance
- **Temporal Retrieval**: **~59x speedup** compared to legacy filters by leveraging GleamDB's sharded temporal sharding.
- **Zero-Copy Joins**: In-memory ETS indices allow for sub-millisecond context window assembly.

## 🛠️ Usage

### Initialize Memory
```gleam
import gclaw/memory

// Persistent memory with automatic schema setup
let mem = memory.init_persistent("agent_memory.db")
```

### Remember Fact (with Auto-Embedding)
```gleam
import gclaw/fact as gfact
import gleamdb/fact

let eid = fact.deterministic_uid("fact_1")
let mem = memory.remember_semantic(mem, [
    #(eid, gfact.msg_content, fact.Str("Apple is a fruit"))
], embedding_vec)
```

### Recall Hybrid Context
```gleam
let context = memory.get_context_window(mem, session_id, 5, query_vec)
// Returns list of strings: ["user: Apple is a fruit", ...]
```

## 🧪 Development
```sh
gleam run   # Run the project
gleam test  # Run the tests (including persistence & hybrid verification)
```

---
*Part of the Gswarm Intelligence Fabric*
