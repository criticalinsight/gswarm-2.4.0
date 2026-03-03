import gleam/option.{type Option, None}
import gleam/result
import gleam/dict
import gleamdb
import gleamdb/fact.{Str}
import gleamdb/shared/types.{Var, Val}
import gleam/list
import gleam/string

pub type PostStatus {
  Draft
  Published
  Archived
}

pub opaque type Post {
  Post(
    id: String,
    title: String,
    slug: String,
    content: String,
    status: PostStatus,
    published_at: Option(Int),
    featured_image: Option(String),
    section_type: String,
  )
}

pub fn get_id(post: Post) -> String {
  post.id
}

pub fn get_title(post: Post) -> String {
  post.title
}

pub fn get_slug(post: Post) -> String {
  post.slug
}

pub fn get_content(post: Post) -> String {
  post.content
}

pub fn get_status(post: Post) -> PostStatus {
  post.status
}

pub fn get_published_at(post: Post) -> Option(Int) {
  post.published_at
}

pub fn get_featured_image(post: Post) -> Option(String) {
  post.featured_image
}

pub fn get_section_type(post: Post) -> String {
  post.section_type
}

pub fn new_post(id: String, title: String, slug: String, content: String) -> Post {
  Post(id, title, slug, content, Draft, None, None, "content")
}

pub fn with_status(post: Post, status: PostStatus) -> Post {
  Post(..post, status: status)
}

pub fn with_featured_image(post: Post, image: Option(String)) -> Post {
  Post(..post, featured_image: image)
}

pub fn with_section_type(post: Post, section_type: String) -> Post {
  Post(..post, section_type: section_type)
}

pub fn validate_post(post: Post) -> Result(Post, List(String)) {
  let errors = []
  let errors = case is_valid_slug(post.slug) {
    True -> errors
    False -> ["Invalid slug format (lowercase alphanumeric and hyphens only)", ..errors]
  }
  let errors = case string.length(post.title) {
    l if l > 0 && l < 200 -> errors
    _ -> ["Title must be between 1 and 200 characters", ..errors]
  }
  
  case errors {
    [] -> Ok(post)
    _ -> Error(errors)
  }
}

pub fn save_post(db: gleamdb.Db, post: Post) -> Result(Nil, List(String)) {
  use validated_post <- result.try(validate_post(post) |> result.map_error(fn(e) { e }))
  
  let eid = fact.deterministic_uid(validated_post.id)
  
  let facts = [
    #(eid, "cms.post/id", Str(validated_post.id)),
    #(eid, "cms.post/title", Str(sanitize_html(validated_post.title))),
    #(eid, "cms.post/slug", Str(validated_post.slug)),
    #(eid, "cms.post/content", Str(sanitize_html(validated_post.content))),
    #(eid, "cms.post/status", Str(status_to_string(validated_post.status))),
    #(eid, "cms.post/section_type", Str(validated_post.section_type)),
  ]
  
  // Wrap in atomic transaction
  case gleamdb.transact(db, facts) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(["Database transaction failed"])
  }
}

pub fn get_post_by_slug(db: gleamdb.Db, slug: String) -> Result(Post, Nil) {
  let q = [
    gleamdb.p(#(Var("e"), "cms.post/slug", Val(Str(slug)))),
    gleamdb.p(#(Var("e"), "cms.post/id", Var("id"))),
    gleamdb.p(#(Var("e"), "cms.post/title", Var("title"))),
    gleamdb.p(#(Var("e"), "cms.post/content", Var("content"))),
    gleamdb.p(#(Var("e"), "cms.post/status", Var("status"))),
    gleamdb.p(#(Var("e"), "cms.post/section_type", Var("section_type"))),
  ]
  
  let res = gleamdb.query(db, q)
  case res.rows {
    [_row, ..] -> {
      let assert Ok(Str(id)) = gleamdb.get_one(db, fact.Lookup(#("cms.post/slug", Str(slug))), "cms.post/id")
      let assert Ok(Str(title)) = gleamdb.get_one(db, fact.Lookup(#("cms.post/slug", Str(slug))), "cms.post/title")
      let assert Ok(Str(content)) = gleamdb.get_one(db, fact.Lookup(#("cms.post/slug", Str(slug))), "cms.post/content")
      let assert Ok(Str(status)) = gleamdb.get_one(db, fact.Lookup(#("cms.post/slug", Str(slug))), "cms.post/status")
      
      Ok(Post(
        id: id,
        title: title,
        slug: slug,
        content: content,
        status: string_to_status(status),
        published_at: None, // Simplified for now
        featured_image: None,
        section_type: case gleamdb.get_one(db, fact.Lookup(#("cms.post/slug", Str(slug))), "cms.post/section_type") {
          Ok(Str(s)) -> s
          _ -> "content"
        },
      ))
    }
    _ -> Error(Nil)
  }
}

pub fn status_to_string(status: PostStatus) -> String {
  case status {
    Draft -> "draft"
    Published -> "published"
    Archived -> "archived"
  }
}

pub fn string_to_status(status: String) -> PostStatus {
  case status {
    "published" -> Published
    "archived" -> Archived
    _ -> Draft
  }
}

pub fn sanitize_html(input: String) -> String {
  // Basic HTML sanitization for hardening
  input
  |> string.replace("<script", "&lt;script")
  |> string.replace("javascript:", "no-js:")
  |> string.replace("onclick", "no-click")
}

pub fn is_valid_slug(slug: String) -> Bool {
  // Native robustness: Check for allowed characters without regex dependency
  let allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
  case slug {
    "" -> False
    _ -> {
      slug 
      |> string.to_graphemes
      |> list.all(fn(c) { string.contains(allowed, c) })
    }
  }
}

/// Fetch all published posts in a single query pass (no N+1).
pub fn get_all_published(db: gleamdb.Db) -> List(Post) {
  let q = [
    gleamdb.p(#(Var("e"), "cms.post/status", Val(Str("published")))),
    gleamdb.p(#(Var("e"), "cms.post/id", Var("id"))),
    gleamdb.p(#(Var("e"), "cms.post/title", Var("title"))),
    gleamdb.p(#(Var("e"), "cms.post/slug", Var("slug"))),
    gleamdb.p(#(Var("e"), "cms.post/content", Var("content"))),
    gleamdb.p(#(Var("e"), "cms.post/section_type", Var("section_type"))),
  ]
  let res = gleamdb.query(db, q)
  list.filter_map(res.rows, fn(row) {
    case
      dict.get(row, "id"),
      dict.get(row, "title"),
      dict.get(row, "slug"),
      dict.get(row, "content"),
      dict.get(row, "section_type")
    {
      Ok(Str(id)), Ok(Str(title)), Ok(Str(slug)), Ok(Str(content)), Ok(Str(section_type)) ->
        Ok(Post(id, title, slug, content, Published, None, None, section_type))
      _, _, _, _, _ -> Error(Nil)
    }
  })
}
