import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/dynamic/decode
import gleamdb
import gleamdb/gleamcms/db/post
import simplifile

pub type LegacyPost {
  LegacyPost(
    id: String,
    title: String,
    slug: String,
    content_md: String,
    status: String,
    published_at: Option(Int),
    tags: List(String),
  )
}

fn legacy_post_decoder() {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use slug <- decode.field("slug", decode.string)
  use content_md <- decode.field("content_md", decode.string)
  use status <- decode.field("status", decode.string)
  use published_at <- decode.field("published_at", decode.optional(decode.int))
  use tags <- decode.field("tags", decode.list(decode.string))
  decode.success(LegacyPost(id, title, slug, content_md, status, published_at, tags))
}

pub fn run_import(db: gleamdb.Db, json_path: String) -> Result(Int, String) {
  case simplifile.read(json_path) {
    Ok(content) -> {
      let decoder = decode.list(legacy_post_decoder())
      case json.parse(content, decoder) {
        Ok(legacy_posts) -> {
          list.each(legacy_posts, fn(lp) {
            let p = post.new_post(
              lp.id,
              lp.title,
              lp.slug,
              lp.content_md,
            )
            |> post.with_status(post.string_to_status(lp.status))
            
            let _ = post.save_post(db, p)
          })
          Ok(list.length(legacy_posts))
        }
        Error(_) -> Error("Could not decode JSON")
      }
    }
    Error(_) -> Error("Could not read file")
  }
}
