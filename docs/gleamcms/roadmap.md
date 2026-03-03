# GleamCMS Roadmap 🧙🏾‍♂️

> "The only way to go fast, is to go well." — Robert C. Martin

GleamCMS has established a sovereign foundation. The next phases focus on **Experience**, **Media**, and **Extensibility**.

## Phase 5: Theming & Templates (v2.3.0) ✅
- [x] **Functional Components**: Implemented pure `theme.gleam` for type-safe layouts.
- [x] **Theme Contract**: Defined `Type Theme` to enforce consistent theming structure.
- [x] **Dark Mode**: Integrated client-side toggle with CSS variable injection.

## Phase 6: Media Sovereignty (v2.4.0) ✅
- [x] **CAS Storage**: All assets are deduplicated via SHA-256 content addressing.
- [x] **IPFS Bridge**: Simulated pinning for decentralized availability.
- [x] **Verification**: Scripted proof of asset consistency.

## Phase 7: Theme Proliferation (v2.5.0) ✅
- [x] **Parametric Generator**: `configurable.gleam` yields infinite themes.
- [x] **Library**: 50 pre-configured themes (Cyberpunk, Nord, Coffee, etc.).
- [x] **CSS Injection**: Dynamic styling via `:root` variables.

## Phase 8: The AI Site Architect (v2.6.0) ✅
- [x] **Generative Site Stories**: AI-driven 4-5 section landing page composition.
- [x] **Sectional Facts**: Native `hero`, `features`, `stats`, and `cta` block manifestation.
- [x] **Premium Flourishes**: Scroll Reveal, Grid Rhythm, and Hero Split variations.

## Phase 9: Collaborative Workflows (v2.7.0)
**Goal**: Enable multi-agent collaboration on shared content.
- [ ] **CRDT Integration**: Conflict-Free Replicated Data Types for real-time collaborative editing in the Lustre editor.
- [ ] **Approval Pipelines**: "Request Review" state transition enforcing a second-party approval before `Published`.
- [ ] **Agent Comments**: Meta-facts allowing AI agents (Gswarm) to leave comments/suggestions on drafts.

## Phase 9: Extensibility (v3.0.0)
**Goal**: Open the platform to user-defined logic.
- [ ] **Middleware Plugins**: Hook system for the Wisp router.
- [ ] **WASM Runtime**: Safely execute user-provided build plugins (e.g. syntax highlighters, math renderers) without recompiling the core.
- [ ] **Fediverse Connection**: ActivityPub implementation to federate published posts to the wider social web.

---
*Roadmap subject to the constraints of Simplicity.* 
