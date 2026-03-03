import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleamdb/gleamcms/db/post.{type Post}
import gleamdb/gleamcms/theme.{type Theme, Theme}

pub fn new() -> Theme {
  Theme(
    layout: layout,
    post_view: post_view,
    archive_view: archive_view,
  )
}

pub fn layout(title: String, body: String) -> String {
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>" <> title <> " - GleamCMS</title>
  <link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap\">
  <style>
    :root {
      --bg-color: #0f172a;
      --text-color: #f8fafc;
      --accent-color: #3b82f6;
      --border-color: #1e293b;
      --card-bg: #1e293b99;
    }
    body {
      font-family: 'Inter', sans-serif;
      background-color: var(--bg-color);
      color: var(--text-color);
      margin: 0;
      line-height: 1.6;
    }
    .container {
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
    }
    nav {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 2rem;
      border-bottom: 1px solid var(--border-color);
      margin-bottom: 2rem;
    }
    .logo {
      font-weight: 700;
      font-size: 1.5rem;
      color: var(--accent-color);
      text-decoration: none;
    }
    .nav-links a {
      color: var(--text-color);
      text-decoration: none;
      margin-left: 1.5rem;
      font-weight: 500;
      opacity: 0.8;
      transition: opacity 0.2s;
    }
    .nav-links a:hover {
      opacity: 1;
      color: var(--accent-color);
    }
    article header {
      margin-bottom: 2rem;
    }
    article h1 {
      font-size: 2.5rem;
      margin-bottom: 0.5rem;
      line-height: 1.2;
    }
    .meta {
      color: #94a3b8;
      font-size: 0.9rem;
    }
    .content {
      font-size: 1.125rem;
    }
    footer {
      margin-top: 4rem;
      padding-top: 2rem;
      border-top: 1px solid var(--border-color);
      text-align: center;
      color: #64748b;
      font-size: 0.9rem;
    }
  </style>
  <script>
    function toggleTheme() {
      const root = document.documentElement;
      const current = root.style.getPropertyValue('--bg-color');
      
      if (current === '#ffffff') {
        root.style.setProperty('--bg-color', '#0f172a');
        root.style.setProperty('--text-color', '#f8fafc');
        root.style.setProperty('--card-bg', '#1e293b99');
      } else {
        root.style.setProperty('--bg-color', '#ffffff');
        root.style.setProperty('--text-color', '#0f172a');
        root.style.setProperty('--card-bg', '#f1f5f9');
      }
    }
  </script>
</head>
<body>
  <div class=\"container\">
    " <> navbar() <> "
    <main>
      " <> body <> "
    </main>
    " <> footer() <> "
  </div>
</body>
</html>"
}

pub fn navbar() -> String {
  "<nav>
    <a href=\"/\" class=\"logo\">GleamCMS</a>
    <div class=\"nav-links\">
      <a href=\"/\">Home</a>
      <a href=\"/about\">About</a>
      <a href=\"/rss.xml\">RSS</a>
      <button onclick=\"toggleTheme()\" style=\"margin-left: 1rem; background: none; border: 1px solid var(--accent-color); color: var(--accent-color); padding: 0.25rem 0.5rem; border-radius: 4px; cursor: pointer;\">Theme</button>
    </div>
  </nav>"
}

pub fn footer() -> String {
  "<footer>
    <p>&copy; 2026 Sovereign Individual. Built with GleamCMS.</p>
  </footer>"
}

pub fn post_view(post: Post) -> String {
  let date_str = case post.get_published_at(post) {
    Some(ts) -> "Published on " <> int_to_string(ts)
    None -> "Draft"
  }

  "<article>
    <header>
      <h1>" <> post.get_title(post) <> "</h1>
      <div class=\"meta\">" <> date_str <> "</div>
    </header>
    <div class=\"content\">
      " <> post.get_content(post) <> "
    </div>
  </article>"
}

pub fn archive_view(posts: List(Post)) -> String {
  let list_items = list.map(posts, fn(p) {
    "<li>
       <a href=\"/posts/" <> post.get_slug(p) <> ".html\">" <> post.get_title(p) <> "</a>
     </li>"
  }) |> list.fold("", fn(acc, item) { acc <> item })

  "<h1>Archive</h1>
   <ul>" <> list_items <> "</ul>"
}

fn int_to_string(i: Int) -> String {
  int.to_string(i)
}
