import gleamdb/gleamcms/db/post.{type Post}

pub type Theme {
  Theme(
    layout: fn(String, String) -> String,
    post_view: fn(Post) -> String,
    archive_view: fn(List(Post)) -> String,
  )
}
