# GleamCMS: Retrospective Learnings 🧙🏾‍♂️

> "We can only reason about what is true. We cannot reason about what 'changed'."

Building GleamCMS on top of the Sovereign Engine (GleamDB) revealed several deep insights into the nature of Content Management and Fact-Oriented Systems.

## 1. The "Schemaless" Paradox
**Myth:** Fact-based systems are "schemaless" and therefore dangerous.
**Reality:** They are *structurally* schemaless but *semantically* rigid.
- **Learning**: We found that while the database accepts any `(E, A, V)`, the *Application Layer* must enforce rigidity.
- **Solution**: The `validate_post` guard in `post.gleam` was essential. Without it, "junk facts" (e.g. invalid slugs) polluted the store forever.
- **Takeaway**: **Guard at the Gate.** Enforce schema on *write*, not on *read*.

## 2. Sum Types are the Ultimate Router
**Myth:** CMS status workflows need complex state machines stored in DB tables.
**Reality:** A simple Gleam `Sum Type` replaces purely database-driven state logic.
- **Learning**: By defining `PostStatus { Draft | Published | Archived }`, we forced the Static Site Generator to handle every case.
- **Impact**: We eliminated a strict class of bugs where "Scheduled" posts might accidentally leak because a SQL `WHERE` clause missed them. If the type exists, the compiler forces you to handle it.

## 3. De-complected Identity (The Slug)
**Problem**: How do distributed agents update the same post without coordination?
**Solution**: Deterministic Identity (`fact.deterministic_uid`).
- **Learning**: We stopped using auto-incrementing integers. By hashing the Slug to generate the Entity ID, Gswarm (the AI agent) and the Human Editor could independently assert facts about "my-post" without ever talking to each other.
- **Takeaway**: Identity should be intrinsic to the data, not assigned by the storage engine.

## 4. The "Save Loop" Symmetry
**Problem**: Building a separate API and separate Frontend often leads to logic drift.
**Solution**: Shared MVU Types.
- **Learning**: Because `app.gleam` (Editor) and `router.gleam` (Server) share the same `Post` type and validation logic, the frontend can't visually represent an invalid state that the backend would reject.
- **Benefit**: "Correct by Construction" UI.

## 5. Performance: Silicon Saturation vs. IO
**Observation**: Traditional CMSs crawl disk folders to build sites.
**Pivot**: GleamCMS queries memory (ETS).
- **Metric**: Finding all published posts is an O(1) index lookup, not an O(N) IO traversal.
- **Result**: The build time is dominated by HTML string concatenation, not data retrieval.

## 6. Dependency Minimalism (The Hardening)
**Observation**: External packages (e.g., `gleam_regexp`, `lustre_http`) can drift from the core compiler or standard library.
**Solution**: Native Implementation.
- **Learning**: Implementing slug validation with `string.contains` (native) instead of `regex` (external NIF) removed a critical failure point.
- **Takeaway**: In a Sovereign System, **dependencies are liabilities**. If you can implement it in <20 lines of pure Gleam, do not import it.

## 7. The Power of Functional Contracts (Theming)
**Problem**: How to support 50+ themes without dynamic class loading or reflection?
**Solution**: A Type Contract (`pub type Theme { ... }`).
- **Learning**: By defining the *shape* of a theme as a record of functions, we could generate infinite themes using a simple constructor (`configurable.new`).
- **Benefit**: Zero runtime overhead. Switching themes is just passing a different record to the generator function.

## 8. Content is Addressable (Media Sovereignty)
**Problem**: Users upload the same image 10 times, bloating storage.
**Solution**: CAS (Content Addressable Storage).
- **Learning**: Naming files by their SHA-256 hash (`hash.png`) automatically deduplicates storage.
- **Impact**: We don't need a database table to track "duplicates". The filesystem *is* the index. If `exists(hash)`, it's already there.

---
*True simplicity is derived from the absence of intertwined responsibilities.*

## 9. Visual Verification Reveals Silent Bugs
**Observation**: Build compiles. Tests pass. Server starts. But the browser sees a blank page.
**Root Cause**: `wisp.response(401)` with no body is legal Gleam. It is not a useful error message.
**Solution**: Always render a styled HTML body for error responses, not just a status code.
- **Takeaway**: **Playwright CLI is non-negotiable**. A green compile is necessary, not sufficient. Visual verification catches the class of bugs that live in the gap between "the server responded" and "the user saw something useful".

## 10. Routers Must Have a Root Handler
**Observation**: Every HTTP router implicitly handles `/`. Leaving it as a 404 is a broken UX decision, not a valid default.
**Solution**: Added `serve_home` as the catch-all, rendering a styled landing page with links to the admin and health endpoints.
- **Takeaway**: **No dead ends.** A sovereign system acknowledges every request, even if only to redirect or explain itself.

## 11. The Ordered Sequence Problem
**Observation**: Maintaining the order of sections in a "Site Story" required embedding numeric indices in slugs (`my-site-1-hero`). 
- **Learning**: Datalog is inherently set-based and unordered.
- **Engine Improvement**: GleamDB should support a native `Order` attribute type or an `index` primitive in `q.query_at` that preserves the sequence of assertions within a single transaction.

## 12. Fuzzy Ingestion for Noisy Agents
**Observation**: AI agents often output informative text (rate-limit warnings, pleasantries) along with JSON.
- **Learning**: Strict JSON parsing in the ingestor causes brittle failures.
- **Engine Improvement**: GleamDB's `Virtual` predicate tools should include a native `extract_json` utility that recursively finds the largest balanced-bracket block, making sharded ingestion from unreliable sources (LLMs, Scraping) resilient by default.

## 13. Complex Pull Predicates
**Observation**: We had to perform post-query filtering in Gleam to separate "Sections" from "Archive Posts".
- **Learning**: Pulling the entire entity and then filtering in the application layer is inefficient for large entities.
- **Engine Improvement**: Support for **Filtered Pulls** (e.g., `pull(E, [Title, Content], where: SectionType != "content")`) would saturate the engine's read-path and reduce serialization overhead.

## 14. Atomic Fact-Sync Batches
**Observation**: Pushing facts one-by-one to a decentralized node via the bridge can lead to inconsistent intermediate states.
- **Learning**: Distributed synchronization must be transactionally atomic.
- **Engine Improvement**: The `SyncFact` protocol should enforce a "Transaction Barrier," ensuring that all facts in a sync payload are either persisted together or roll back the entire sharded cluster.

## 15. Composite Uniqueness Constraints
**Observation**: We enforce "Slug Uniqueness" in the app layer (`post.gleam`). 
- **Learning**: App-level guards are bypassed by direct `gleamdb.transact` calls.
- **Engine Improvement**: Support for **Schema-Level Composite Uniqueness** (e.g., "Attribute A + Attribute B must be unique across the fabric") would move sanity-checking into the immutable core where it belongs.

---
*GleamDB is not just a database; it is the substrate for Sovereign Intelligence.* 🧙🏾‍♂️
