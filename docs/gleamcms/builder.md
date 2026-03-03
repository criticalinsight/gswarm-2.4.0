# GleamCMS Builder: SSG & Projections 🧙🏾‍♂️

The GleamCMS Builder is a high-performance **Static Site Generator (SSG)** that projects the Datalog fact store into static HTML assets.

## 1. Exhaustive Projections
We leverage Gleam's type system to ensure correctness.

- **Sum Type**: `PostStatus { Draft | Published | Archived }`.
- **Guarantee**: The build process in `generator.gleam` uses exhaustive pattern matching on this type. If a status is not handled, the system will not compile.
- **Auto-Pruning**: Archived and Draft posts are automatically excluded from the public build by the logic engine.

## 2. Dynamic Datalog Queries
The builder does not crawl filesystem folders. It queries the database:

```gleam
let q = [
  gleamdb.p(#(Var("e"), "cms.post/slug", Var("slug"))),
  gleamdb.p(#(Var("e"), "cms.post/status", Val("published")))
]
```

This de-complects the *storage* (Facts) from the *structure* (Slugs).

## 3. Sharded Generation
For large content repositories, the builder leverages `gleamdb/sharded`:

- **Parallelism**: HTML rendering is distributed across all logical CPU cores.
- **Latency**: Sub-second builds for thousand-page sites on M-Series silicon.

### 4.1 Section-Aware Rendering
The builder logic in `configurable.gleam` supports multi-section "Site Stories":
- **Sorting**: Posts are sorted by slug (e.g., `-1-hero`, `-2-features`) to maintain the AI's intended flow.
- **Partitioning**: Content is partitioned into distinct sections (rendered as specific UI components) and regular posts (rendered as archive links).
- **Flourishes**: Scroll Reveal animations and Grid Rhythm are applied based on the `ThemeConfig`.

## 5. Parametric Theme Engine
GleamCMS defines a strict `Theme` contract in `theme.gleam`.
- **Contract**: `pub type Theme { Theme(...) }` enforces that every theme provides consistent layout functions.
- **Generator**: `configurable.gleam` allows generating infinite theme variations from a simple `ThemeConfig` record.
- **Library**: `library.gleam` ships with 50 pre-configured themes (e.g., Cyberpunk, Nord, Solarized).

## 6. Media Sovereignty (CAS)
Assets are managed via a Content-Addressable Storage pipeline:
- **Deduplication**: Files are named by their SHA-256 hash (e.g., `677...E83.png`). Uploading the same file twice results in the same ID.
- **Security**: Strict hash-based filenames prevent directory traversal.
- **Decentralization**: The hashing scheme is compatible with IPFS CIDs, enabling future-proof decentralized hosting.
