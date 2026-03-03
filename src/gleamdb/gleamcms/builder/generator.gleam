import gleam/list
import gleam/string
import gleam/int
import gleamdb
import simplifile
import gleamdb/gleamcms/db/post.{type Post, Published}
import gleamdb/gleamcms/theme.{type Theme}
import gleamdb/gleamcms/builder/theme as theme_provider
import gleamdb/gleamcms/themes/library

pub fn seed_showcase_posts(db: gleamdb.Db) -> Result(Nil, List(String)) {
  let configs = library.get_configs()
  let results = list.index_map(configs, fn(config, i) {
    let id = "showcase-" <> int.to_string(i + 1)
    let title = "Showcase: " <> config.name
    let slug = "showcase-" <> int.to_string(i + 1)
    let content = "# Welcome to " <> config.name <> "\n\nThis post demonstrates the " <> config.name <> " theme in GleamCMS."
    let p = post.new_post(id, title, slug, content)
            |> post.with_status(Published)
    post.save_post(db, p)
  })
  
  case list.filter_map(results, fn(r) { case r { Error(e) -> Ok(e) Ok(_) -> Error(Nil) } }) {
    [] -> Ok(Nil)
    errors -> Error(list.flatten(errors))
  }
}

pub type BuildReport {
  BuildReport(
    theme_name: String,
    pages_written: Int,
    output_dir: String,
    errors: List(String),
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Build one themed site → gleamcms_output/<theme-slug>/
pub fn build(db: gleamdb.Db, theme_name: String) -> BuildReport {
  let slug = slugify(theme_name)
  let output_dir = "gleamcms_output/" <> slug
  let _ = simplifile.create_directory_all(output_dir)

  let posts = post.get_all_published(db)
  let t = theme_provider.get_by_name(theme_name)

  // Per-post pages
  let results = list.map(posts, fn(p) {
    let path = output_dir <> "/" <> post.get_slug(p) <> ".html"
    case simplifile.write(path, render_post(p, t)) {
      Ok(_) -> Ok(path)
      Error(e) -> Error("Failed " <> path <> ": " <> string.inspect(e))
    }
  })

  let errors = list.filter_map(results, fn(r) {
    case r { Error(e) -> Ok(e) Ok(_) -> Error(Nil) }
  })
  let written = list.length(results) - list.length(errors)

  // Index + RSS
  let _ = simplifile.write(output_dir <> "/index.html", render_index(posts, t))
  let _ = simplifile.write(output_dir <> "/feed.xml", render_rss(posts))

  BuildReport(
    theme_name: theme_name,
    pages_written: written + 1,
    output_dir: output_dir,
    errors: errors,
  )
}

/// Build ALL 50 themes → one report per theme.
pub fn build_all(db: gleamdb.Db) -> List(BuildReport) {
  library.get_configs()
  |> list.map(fn(c) { build(db, c.name) })
}

/// Specialized build: 50 sites, each with exactly ONE unique post.
pub fn build_showcase(db: gleamdb.Db) -> List(BuildReport) {
  let _ = simplifile.delete("gleamcms_output")
  let _ = simplifile.create_directory_all("gleamcms_output")
  
  let configs = library.get_configs()
  let posts = post.get_all_published(db)
  
  // Filter for posts created by seed_showcase_posts
  let showcase_posts = list.filter(posts, fn(p) { 
    string.starts_with(post.get_slug(p), "showcase-") 
  })
  
  list.index_map(configs, fn(config, i) {
    // Pick the corresponding showcase post if it exists, otherwise use whatever first is available
    let theme_posts = case list.drop(showcase_posts, i) |> list.first {
      Ok(p) -> [p]
      Error(_) -> case list.first(showcase_posts) {
        Ok(p) -> [p]
        Error(_) -> []
      }
    }
    
    do_build(db, config.name, theme_posts)
  })
}

fn do_build(_db: gleamdb.Db, theme_name: String, theme_posts: List(Post)) -> BuildReport {
  let slug = slugify(theme_name)
  let output_dir = "gleamcms_output/" <> slug
  let _ = simplifile.create_directory_all(output_dir)

  let t = theme_provider.get_by_name(theme_name)

  // Per-post pages
  let results = list.map(theme_posts, fn(p) {
    let path = output_dir <> "/" <> post.get_slug(p) <> ".html"
    case simplifile.write(path, render_post(p, t)) {
      Ok(_) -> Ok(path)
      Error(e) -> Error("Failed " <> path <> ": " <> string.inspect(e))
    }
  })

  let errors = list.filter_map(results, fn(r) {
    case r { Error(e) -> Ok(e) Ok(_) -> Error(Nil) }
  })
  let written = list.length(results) - list.length(errors)

  // Index + RSS
  let _ = simplifile.write(output_dir <> "/index.html", render_index(theme_posts, t))
  let _ = simplifile.write(output_dir <> "/feed.xml", render_rss(theme_posts))

  BuildReport(
    theme_name: theme_name,
    pages_written: written + 1,
    output_dir: output_dir,
    errors: errors,
  )
}

/// List theme slugs that have already been generated on disk.
pub fn list_generated() -> List(String) {
  case simplifile.read_directory("gleamcms_output") {
    Ok(entries) ->
      entries
      |> list.filter(fn(e) { e != "." && e != ".." && !string.contains(e, ".") })
    Error(_) -> []
  }
}

// ---------------------------------------------------------------------------
// Renderers
// ---------------------------------------------------------------------------

fn render_post(p: Post, t: Theme) -> String {
  let content = { t.post_view }(p)
  { t.layout }(post.get_title(p), content)
}

fn render_index(posts: List(Post), t: Theme) -> String {
  let content = { t.archive_view }(posts)
  { t.layout }("Archive", content)
}

fn render_rss(posts: List(Post)) -> String {
  let items = list.map(posts, fn(p) {
    "<item><title>" <> post.get_title(p) <> "</title>"
    <> "<link>/posts/" <> post.get_slug(p) <> "</link></item>"
  })
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  <> "<rss version=\"2.0\"><channel><title>GleamCMS</title><link>/</link>"
  <> string.join(items, "\n")
  <> "</channel></rss>"
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn slugify(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(" ", "-")
}
