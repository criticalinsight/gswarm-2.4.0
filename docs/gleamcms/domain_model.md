# GleamCMS Domain Model 🧙🏾‍♂️

GleamCMS uses **Opaque Types** and **Sum Types** to enforce domain integrity at the compiler level.

## 1. The Post Type
The `Post` record is **opaque**. It cannot be constructed directly by consumers; it must be created via the `new_post` constructor.

```gleam
pub opaque type Post {
  Post(
    id: String,
    title: String,
    slug: String,
    content: String,
    status: PostStatus,
    section_type: String, // "hero", "features", "stats", "cta", "content"
    published_at: Option(Int),
    tags: List(String),
  )
}
```

### Constructor
```gleam
let p = post.new_post(id, title, slug, content)
```
This ensures that every Post has at least the minimum required fields populated.

## 2. Post Status (Sum Type)
We do not use strings for status. We use a **Sum Type**:

```gleam
pub type PostStatus {
  Draft
  Published
  Archived
}
```

- **Draft**: Hidden from the builder.
- **Published**: Included in the build.
- **Archived**: Hidden but preserved in the store.

### Exhaustive Matching
The static site generator (`generator.gleam`) uses `case` statements on this type. If you add a new status, the build will fail until you define how it should be handled.

## 3. Fact Serialization
The domain model includes helper functions to convert the Record into Atomic Facts for GleamDB storage (`transact_fact`).

- `get_post_by_slug` reconstructs the record from raw facts using a Datalog query.
