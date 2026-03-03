# Learnings: Maintenance & Stability (v2.1.1) 🧙🏾‍♂️

## 1. The `int.range` Deprecation
- **Context**: `gleamdb` utilized `int.range` for HNSW layer iteration and sharded parallel startup.
- **Issue**: Newer Gleam stdlib versions deprecated and removed `int.range`, causing build failures in dependent ecosystem projects like `amkabot`.
- **Resolution**: Replaced all instances with `list.fold(list.range(start, end - 1), ...)` pattern.
- **Key Insight**: Core infrastructure libraries must pin dependencies strictly or avoid experimental features. The `list.range` end-inclusive behavior vs. `int.range` behavior required careful off-by-one checks during refactoring.

## 2. Distributed Testing Quirks
- **Context**: Testing `sharded.gleam` requires spawning multiple Erlang processes.
- **Issue**: `gleeunit` aggressive process cleanup can kill supervised children before they initialize.
- **Resolution**: Use `process.sleep` in test setup or explicit synchronization channels (`Subject`) to ensure shards are ready before assertions.

## 3. API Evolution & Semantic Versioning
- **Context**: `gleamdb` v2.1.0 changed `QueryResult` to expose a `.rows` field and `fact.Datom` to include `valid_time`.
- **Impact**: Breaking change for downstream consumers.
- **Action**: Future breaking changes to public structs should be gated behind `vNext` branches or accompanied by migration scripts.
