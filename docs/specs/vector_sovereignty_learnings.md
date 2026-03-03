# Learnings: Vector Sovereignty & Performance Crisis (Phase 42) 🧙🏾‍♂️

## 1. The O(N²) Insertion Trap ✅ RESOLVED
**Issue**: During Gswarm production dogfooding, ingestion slowed to a crawl after 50k facts. CPU hovered at 100% in `vec_index.gleam`.
**Discovery**: The initial vector index implementation used a brute-force neighbor scan. Every new fact insertion was $O(N)$, leading to $O(N^2)$ complexity for the total dataset. At 1,000 facts/sec, the "Wall of Complexity" was hit in less than 60 seconds.
**Solution**: Transitioned to **NSW (Navigable Small-World)** greedy search. 
- **Complexity**: $O(\log N)$ search/insertion.
- **Result**: Cluster initialization time dropped from "Indefinite/Timeout" to < 5 seconds for 100k+ historical datoms.
**Learning**: In a sharded, historical-first database, insertion performance *is* recovery performance. $O(N)$ is unacceptable for any inner-loop index logic.

## 2. The Cost of Dot Product (Normalization) ✅ OPTIMIZED
**Issue**: `cosine_similarity` was recalculating vector magnitudes on every score comparison. 
**Solution**: Enforce **Unit-Vector Normalization** at the API boundary.
- **Pattern**: `sqrt(sum(v_i²)) = 1.0`.
- **Optimization**: Similarity scoring becomes a pure `dot_product`, eliminating expensive `sqrt` and division calls in the inner search loop.
**Learning**: Move non-linear math to the "Sovereign Boundary" (ingestion) to keep the "Engine Core" (query/search) purely linear and fast.

## 3. Shard Recovery Timeouts ✅ FIXED
**Issue**: Parallel shard recovery was timing out at 120s due to the massive volume of historical reductions (billions per process).
**Solution**: 
- Increased internal startup timeouts to 600s.
- Parallelized the recovery scan using `process.spawn` to saturate all CPU cores.
**Learning**: Sharding doesn't just scale capacity; it scales **Recovery Velocity**. By splitting history into $N$ buckets, the "Time to Reach the Tip" is reduced by factor $N$, provided the cluster initialization isn't bottlenecked by global consensus locks.

## 4. Name Registration Hazards ✅ RESOLVED
**Issue**: Sharded nodes attempting to register multiple global handles (e.g., `gleamdb_leader` AND `gleamdb_shard_0`) caused `global: registered under several names` warnings and increased contention in the Erlang `global` module.
**Solution**: Standardized on a single unique global ID per process. Reduced noisy registration attempts during concurrent startups to prevent deadlocks in the distributed name server.
**Learning**: Distributed stability requires "Name Hygiene." Minimize global state to minimize coordination entropy.
