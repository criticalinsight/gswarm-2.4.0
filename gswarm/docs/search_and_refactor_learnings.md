# Learnings: Search Integration & Refactoring (GleamDB v2.1.0) 🧙🏾‍♂️

## 1. Challenges with `gleeunit` and Distributed Systems
- **Observation**: `gleeunit` runs tests in a single BEAM node context. When testing `gleamdb` in distributed mode (which spawns separate node actors), the test runner often terminates or creates race conditions with the database supervision tree.
- **Solution**: Moved integration tests that require a full distributed cluster to a standalone executable (`src/gswarm/search_check.gleam`). This allows the test process to control its own lifecycle and `process.sleep_forever()` if necessary, bypassing the test runner's constraints.

## 2. Native Indexing vs. Filters
- **Observation**: Previous implementations used post-query filtering for prefix matching, which is O(N) scan.
- **Improvement**: Integrating `types.StartsWith` leverages the ART (Adaptive Radix Tree) index for O(k) lookups.
- **Key Takeaway**: Always prefer pushing predicates down to the database engine. If a native predicate exists (`StartsWith`, `Similarity`), use it instead of `list.filter`.

## 3. The `int.range` Deprecation
- **Issue**: `gleamdb` relied on `int.range` which was deprecated and removed in recent Gleam stdlib versions, causing build failures in dependent projects like `amkabot`.
- **Fix**: Replaced usage with `list.fold(list.range(0, count - 1), ...)` pattern.
- **Learning**: Avoid relying on deprecated or experimental stdlib features in core libraries. When upgrading dependencies, check changelogs for breaking changes in standard library functions.

## 4. Schema Evolution & Type Safety
- **Observation**: `gleamdb` v2.1.0 introduced changes to `QueryResult` (accessing `.rows` field) and `Datom` (adding `valid_time`).
- **Impact**: Consuming projects (`amkabot`) failed to compile until updated.
- **Mitigation**: When updating a core library like `gleamdb`, always run `gleam build` on all dependent projects immediately to catch API drifts. Semantic versioning is crucial, but manual verification is still needed for cross-repo dependencies.
