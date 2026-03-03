import gleam/list
import gleam/string
import gleamdb/gleamcms/db/post.{type Post}
import gleamdb/gleamcms/theme.{type Theme, Theme}

pub type ThemeConfig {
  ThemeConfig(
    name: String,
    bg_color: String,
    text_color: String,
    accent_color: String,
    border_color: String,
    card_bg: String,
    font_family: String,
    layout_style: String,
    shadow_depth: String,
    border_radius: String,
    spacing_scale: String,
    custom_flourish: String,
  )
}

pub fn new(config: ThemeConfig) -> Theme {
  Theme(
    layout: fn(title, body) { layout(config, title, body) },
    post_view: post_view,
    archive_view: archive_view,
  )
}

fn layout(config: ThemeConfig, title: String, body: String) -> String {
  let shadow = case config.shadow_depth {
    "elevated" -> "0 10px 25px -5px rgba(0,0,0,0.3), 0 8px 10px -6px rgba(0,0,0,0.3)"
    "subtle" -> "0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -2px rgba(0,0,0,0.1)"
    _ -> "none"
  }
  
  let radius = case config.border_radius {
    "round" -> "2rem"
    "soft" -> "0.75rem"
    "sharp" -> "0"
    _ -> "0.5rem"
  }

  let spacing = case config.spacing_scale {
    "airy" -> "4rem"
    "compact" -> "1rem"
    _ -> "2rem"
  }

  let layout_class = "layout-" <> config.layout_style

  "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>" <> title <> " - " <> config.name <> "</title>
  <link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=" <> config.font_family <> ":wght@400;600;700&display=swap\">
  <style>
    :root {
      --bg-color: " <> config.bg_color <> ";
      --text-color: " <> config.text_color <> ";
      --accent-color: " <> config.accent_color <> ";
      --border-color: " <> config.border_color <> ";
      --card-bg: " <> config.card_bg <> ";
      --shadow: " <> shadow <> ";
      --radius: " <> radius <> ";
      --spacing: " <> spacing <> ";
    }
    body {
      font-family: '" <> config.font_family <> "', sans-serif;
      background-color: var(--bg-color);
      color: var(--text-color);
      margin: 0;
      line-height: 1.6;
    }
    .container {
      max-width: 1000px;
      margin: 0 auto;
      padding: var(--spacing);
    }
    nav {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 1.5rem 0;
      margin-bottom: var(--spacing);
    }
    .logo {
      font-weight: 700;
      font-size: 1.5rem;
      color: var(--accent-color);
      text-decoration: none;
      letter-spacing: -0.025em;
    }
    .nav-links a {
      color: var(--text-color);
      text-decoration: none;
      margin-left: 1.5rem;
      font-weight: 500;
      opacity: 0.8;
      transition: all 0.2s ease;
    }
    .nav-links a:hover {
      opacity: 1;
      color: var(--accent-color);
      transform: translateY(-1px);
    }
    header.hero {
      padding: 4rem 0;
      text-align: center;
      background: var(--card-bg);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      margin-bottom: var(--spacing);
    }
    article {
      background: var(--card-bg);
      padding: 3rem;
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      border: 1px solid var(--border-color);
    }
    .meta {
      color: #94a3b8;
      font-size: 0.9rem;
      margin-bottom: 1rem;
    }
    .content {
      font-size: 1.125rem;
    }
    footer {
      margin-top: 4rem;
      padding: 4rem 0;
      border-top: 1px solid var(--border-color);
      text-align: center;
      color: #64748b;
      font-size: 0.9rem;
    }
    /* Global Section Transitions */
    .section {
      opacity: 0;
      transform: translateY(20px);
      transition: opacity 0.8s ease-out, transform 0.8s ease-out;
    }
    .section.revealed {
      opacity: 1;
      transform: translateY(0);
    }

    /* Grid Rhythm */
    .grid-container {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: var(--spacing);
    }
    
    .stats-grid {
      display: flex;
      justify-content: space-around;
      gap: var(--spacing);
      text-align: center;
    }

    /* Hero Variations */
    .hero-section {
      min-height: 60vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: calc(var(--spacing) * 2);
    }
    
    .layout-hero-split .hero-section {
      justify-content: flex-start;
      text-align: left;
    }
    
    .hero-content {
      max-width: 800px;
    }
    
    .accent-bar {
      width: 60px;
      height: 4px;
      background: var(--accent-color);
      margin-bottom: 1.5rem;
    }

    " <> config.custom_flourish <> "
  </style>
  <script>
    document.addEventListener('DOMContentLoaded', () => {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            entry.target.classList.add('revealed');
          }
        });
      }, { threshold: 0.1 });
      
      document.querySelectorAll('.section').forEach(s => observer.observe(s));
    });
  </script>
</head>
<body class=\"" <> layout_class <> "\">
  <div class=\"container\">
    " <> navbar(config) <> "
    <main>
      " <> body <> "
    </main>
    " <> footer(config) <> "
  </div>
</body>
</html>"
}

fn navbar(config: ThemeConfig) -> String {
  "<nav>
    <a href=\"/\" class=\"logo\">" <> config.name <> "</a>
    <div class=\"nav-links\">
      <a href=\"/\">Home</a>
      <a href=\"/about\">About</a>
      <a href=\"/rss.xml\">RSS</a>
    </div>
  </nav>"
}

fn footer(config: ThemeConfig) -> String {
  "<footer>
    <p>&copy; 2026 " <> config.name <> ". Built with GleamCMS.</p>
  </footer>"
}

// Reusing standard views for now, but they could also be parameterized
// Section-aware post view dispatch
fn post_view(post: Post) -> String {
  case post.get_section_type(post) {
    "hero" -> render_hero_section(post)
    "features" -> render_features_section(post)
    "stats" -> render_stats_section(post)
    "cta" -> render_cta_section(post)
    _ -> render_content_section(post)
  }
}

fn render_hero_section(post: Post) -> String {
  "<header class=\"section hero-section\">
    <div class=\"hero-content\">
      <div class=\"accent-bar\"></div>
      <h1>" <> post.get_title(post) <> "</h1>
      <div class=\"content\">" <> post.get_content(post) <> "</div>
    </div>
  </header>"
}

fn render_features_section(post: Post) -> String {
  "<section class=\"section features-section\">
    <h2>" <> post.get_title(post) <> "</h2>
    <div class=\"grid-container\">" <> post.get_content(post) <> "</div>
  </section>"
}

fn render_stats_section(post: Post) -> String {
  "<section class=\"section stats-section\">
    <div class=\"stats-grid\">" <> post.get_content(post) <> "</div>
  </section>"
}

fn render_cta_section(post: Post) -> String {
  "<section class=\"section cta-section\">
    <h2>" <> post.get_title(post) <> "</h2>
    <div class=\"cta-content\">" <> post.get_content(post) <> "</div>
  </section>"
}

fn render_content_section(post: Post) -> String {
  "<article class=\"section content-section\">
    <header>
      <h1>" <> post.get_title(post) <> "</h1>
    </header>
    <div class=\"content\">
      " <> post.get_content(post) <> "
    </div>
  </article>"
}

fn archive_view(posts: List(Post)) -> String {
  // Sort by slug to preserve the numeric index for Site Stories
  let sorted_posts = list.sort(posts, fn(a, b) {
    string.compare(post.get_slug(a), post.get_slug(b))
  })

  // Filter for sections vs regular posts
  let #(sections, regular) = list.partition(sorted_posts, fn(p) {
    post.get_section_type(p) != "content"
  })

  let section_html = list.map(sections, post_view) |> string.join("\n")
  
  let regular_links = list.map(regular, fn(p) {
    "<li>
       <a href=\"/posts/" <> post.get_slug(p) <> ".html\">" <> post.get_title(p) <> "</a>
     </li>"
  }) |> string.join("\n")

  let archive_section = case regular {
    [] -> ""
    _ -> "<section class=\"section archive-section\">
            <h2>Latest Posts</h2>
            <ul>" <> regular_links <> "</ul>
          </section>"
  }

  section_html <> "\n" <> archive_section
}
