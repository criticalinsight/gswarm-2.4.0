# PRD: Adaptive Performance (Database Cracking)

- **Status**: Draft
- **Priority**: P0
- **Owner**: Rich Hickey 🧙🏾‍♂️

## Overview
GleamDB Phase 56 implements "Database Cracking"—a technique for self-tuning indices that are built incrementally as a side-effect of query execution. This eliminates the need for manual index configuration and provides JIT optimization for analytical workloads.

## User Stories
- **As a Developer**, I want to run range queries on unindexed attributes without performance penalties over time, so that I don't have to manually tune schemas.
- **As a Data Scientist**, I want the database to automatically stabilize its most-queried paths, so that repeated analytical aggregations become faster without human intervention.

## Acceptance Criteria
### Success Path
- **Given** a `Columnar` attribute with $N$ random values.
- **When** a range query (e.g., `?val > 50`) is executed.
- **Then** the engine scans the data AND partitions the `ColumnChunk` into two segments ($<50$ and $\ge 50$).
- **When** a subsequent query for `?val > 75` is executed.
- **Then** the engine only scans the $\ge 50$ segment and further sub-partitions it.
- **Result**: Query latency for the second query must be significantly lower than the first.

### Failure/Resilience Path
- **Given** high concurrent query load.
- **When** multiple queries attempt to crack the same chunk.
- **Then** the system must maintain consistency, ensuring no data is lost or duplicated during the JIT reorganization.
- **Constraint**: Cracking must not exceed a memory ceiling (150% of raw data size).

## Technical Implementation

### Database Evolution
#### [MODIFY] [fact.gleam](file:///Users/brixelectronics/Documents/mac/gswarm/src/gleamdb/fact.gleam)
- Add `CrackingBuffer` to `ColumnChunk`:
  ```gleam
  pub type ColumnChunk {
    ColumnChunk(
      values: List(Value),
      partitions: List(Partition), // New: offsets defining cracked segments
    )
  }
  ```

### Data Flow
1. **Query Engine** receives range predicate.
2. **Navigator** checks `ColumnChunk.partitions` for relevant segments.
3. **Execution Layer** scans minimal segments.
4. **Side-Effect**: Updated `ColumnChunk` (more partitions) is returned and merged into `DbState`.

## Security & Validation
- **Input Validation**: Range predicates must be checked for type compatibility with the attribute's schema before cracking.
- **DoS Mitigation**: Implement a "Cracking Quota" per query to prevent a single complex query from reorganizing too many chunks and causing tail-latency spikes.

## Pre-Mortem Analysis
- **Why will this fail?**
  - **Memory Pressure**: Rapid partitioning of many small segments could lead to overhead that exceeds the benefits of the scan reduction.
  - **Race Conditions**: In a distributed environment (v2.x), keeping cracked states synchronized across shards might "complect" the state transfer.
- **Mitigation**: 
  - Cap partitioning depth (e.g., max 256 segments per chunk).
  - Treat cracked state as an "Advisory Cache"—it's okay if a follower doesn't have the latest cracked state, they'll just scan more.
