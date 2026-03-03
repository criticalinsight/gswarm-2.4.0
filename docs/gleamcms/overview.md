# GleamCMS Overview 🧙🏾‍♂️

GleamCMS is a **Fact-Oriented Content Management System** built on top of the GleamDB Datalog engine. It treats content as a set of atomic assertions (Facts) rather than rigid documents, enabling decentralized editing, deep history, and type-safe projections.

## 🧬 Philosophy

### 1. Facts over Documents
Traditional CMSs store posts as JSON blobs or SQL rows. GleamCMS stores **Facts**:
- `(PostID, "cms.post/title", "Hickey's Guide to DBs")`
- `(PostID, "cms.post/status", "published")`

This "Rama Pattern" de-complects the *state* of the content from any specific *schema*.

### 2. Projections are Pure Functions
Static Site Generation in GleamCMS is a pure function:
`Database -> HTML`
Because the database is an immutable value, the generator can produce consistent views of the site without lock-contention.

### 3. Decentralized Identity
Using `fact.deterministic_uid` (derived from slugs or external IDs), multiple agents (Gswarm, Sly, Human Editors) can contribute to the same post without a central "Coordinator" process.

## 🏗️ Architecture

- **Engine**: GleamDB (v2.2.0 Sovereign).
- **Store**: Mnesia (Distributed Substrate) or SQLite (Durable Log).
- **Architect**: **AI Site Architect** for generative structural composition. [Deep Dive](../features/ai_architect.md)
- **API**: Wisp-based REST/Fact-Sync Bridge.
- **Frontend**: Lustre MVU for the interactive editor.
- **Generator**: Sharded SSG for parallel HTML production.
- **Theming**: Parametric Engine supporting 50+ configurable designs. [See Gallery](gallery.md)
- **Media**: Content-Addressable Storage (CAS) for sovereign asset management.

## 🎯 Use Cases
- **Autonomous Agents**: Gswarm pushing market sentiment directly into blog posts.
- **Micro-Sovereignty**: Self-hosted, low-resource CMS for independent researchers.
- **Durable History**: Projects requiring full audit logs of every content change.
