# GleamCMS Security & Hardening 🧙🏾‍♂️

Security in GleamCMS is built on two pillars: **Input Validation** (Correctness) and **Transactional Integrity** (Consistency).

## 1. Input Validation (Schema Guards)
Content cannot be persisted unless it passes the `validate_post` guard.

- **Slugs**: Must be alphanumeric (`[a-z0-9-]`) to prevent path traversal issues.
- **Titles**: Must be between 1 and 200 characters.
- **HTML**: Stripped of `<script>` tags and dangerous attributes (`onclick`, `javascript:`) before reaching the store.
- **Custom Flourishes**: AI-generated CSS flourishes are limited to safe properties (colors, borders, shadows, transitions) and are reviewed/filtered before injection into the `:root` scope.
- **Sovereign Token**: The Sync API requires a `Bearer` token validated by `require_admin` middleware.

## 2. Transactional Integrity
GleamDB guarantees that multi-fact updates are **atomic**.

- **Example**: Updating a post title (Attribute 1) and status (Attribute 2).
- **Behavior**: If either fails (e.g. malformed JSON), the entire transaction rolls back. The database is never left in a partial state.

## 3. Observability
Security is verified through observability.

- **Structured Logging**: Every successful publication is logged with `info` level. Every failed validation is logged with `warning`.
- **Health Check**: The `/health` endpoint allows monitoring systems to verify the responsiveness of the Fact Store.

## 4. Rate Limiting (Roadmap)
Future versions will include a sliding window rate limiter for the `/api/facts/sync` endpoint to prevent ingestion floods.
