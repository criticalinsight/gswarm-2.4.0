# GleamCMS API Guide 🧙🏾‍♂️

GleamCMS provides two primary interfaces for content manipulation: the **Fact-Sync Bridge** (External/Distributed) and the **Post Module** (Internal/Gleam).

## 1. Fact-Sync Bridge (REST)
The Fact-Sync Bridge allows decentralized agents to update the CMS without awareness of the high-level Post schema.

### Synchronize Facts
- **Endpoint**: `POST /api/facts/sync`
- **Auth**: `Authorization: Bearer <sovereign-token>`
- **Payload**:
```json
[
  {
    "eid": "post-slug-1",
    "attr": "cms.post/sentiment",
    "val": 0.85
  },
  {
    "eid": "post-slug-1",
    "attr": "cms.post/risk-level",
    "val": "low"
  }
]
```

### AI Design Generation
- **Endpoint**: `POST /api/ai/design`
- **Auth**: `Authorization: Bearer <sovereign-token>`
- **Payload**:
```json
{
  "prompt": "A landing page for a boutique hotel..."
}
```
- **Response**: Returns the generated `ThemeConfig` and manifests 4-5 `Post` sections in the database.

## 3. Publication API
Used by the Interactive Editor to submit full content updates.

- **Endpoint**: `POST /api/publish`
- **Schema**:
```json
{
  "title": "My New Post",
  "slug": "my-new-post",
  "content": "Rich Hickey said...",
  "status": "published"
}
```

## 3. Internal Gleam API
The `gleamdb/gleamcms/db/post` module provides type-safe abstractions.

### Validating and Saving
```gleam
import gleamdb/gleamcms/db/post

let p = post.new_post(id, title, slug, content)
  |> post.with_status(post.Published)

case post.save_post(db, p) {
  Ok(_) -> // Success
  Error(errors) -> // Validation failed (e.g. invalid slug)
}
```

### Querying
```gleam
import gleamdb/gleamcms/db/post

// Get a single post by slug
let assert Ok(p) = post.get_post_by_slug(db, "my-new-post")

// Get status
let status = post.get_status(p)
```

## 4. Analytical Stats
- **Endpoint**: `GET /admin/stats`
- **Function**: Returns a live count of all posts in the store using Distributed Aggregates.
