# Contributing to GleamDB 🧙🏾‍♂️

Thank you for your interest in contributing to the Citadel. GleamDB follows strict architectural and versioning principles to ensure long-term stability and resilience.

## Semantic Versioning & Breaking Changes

GleamDB adheres to [Semantic Versioning](https://semver.org/):

1.  **Major** versions (and `0.x` bumping to `0.y`) contain incompatible API changes.
2.  **Minor** versions add functionality in a backward-compatible manner.
3.  **Patch** versions contain backward-compatible bug fixes.

### 🚨 Breaking Changes Policy

**Rich Hickey Rule**: "A breaking change is a violation of a promise."

- **Public Structs**: Changes to public structs (e.g., adding fields to `QueryResult`, `Datom`) are **BREAKING**.
- **Mitigation**:
    1.  **Gate behind `vNext`**: If a change is radical, develop it in a `vNext` branch or behind a feature flag until a Major release.
    2.  **Migration Scripts**: If an update changes the on-disk format or required schema, you **MUST** provide a migration script or clear path.
    3.  **Deprecation**: Prefer adding new functions/types and deprecating old ones over mutating existing signatures.

### Example: The `int.range` Incident
When `int.range` was deprecated in the stdlib, we replaced it with `list.range` + `list.fold` without changing the public API of `vec_index`. This is the gold standard: internal refactoring should not break external consumers.

## Code Style

- **Decomplection**: Separation of concerns is paramount. Do not entangle separate domains (e.g., persistence and logic).
- **Format**: Run `gleam format` before committing.
- **Tests**: All new features must be accompanied by `gleeunit` tests.

## Pull Requests

- **Focused**: PRs should do one thing well.
- **Verified**: Verify that `gleeunit` passes locally. Note that distributed tests may require specific setup (see `docs/maintenance_learnings.md`).
