import wisp.{type Request, type Response}
import gleam/list
import gleam/http
import gleam/json
import gleam/dynamic/decode
import gleam/result
import gleam/string
import gleam/int
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{Var}
import gleamdb/gleamcms/editor/app as editor
import gleamdb/gleamcms/db/post.{Published}
import gleamdb/gleamcms/builder/generator
import gleamdb/gleamcms/ai/designer
import logging

pub type PublishRequest {
  PublishRequest(title: String, slug: String, content: String)
}

pub type SyncFact {
  SyncFact(eid: String, attr: String, val: String)
}

fn sync_fact_decoder() {
  use eid <- decode.field("eid", decode.string)
  use attr <- decode.field("attr", decode.string)
  use val <- decode.field("val", decode.string)
  decode.success(SyncFact(eid:, attr:, val:))
}

fn publish_request_decoder() {
  use title <- decode.field("title", decode.string)
  use slug <- decode.field("slug", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(PublishRequest(title:, slug:, content:))
}

pub fn handle_request(req: Request, db: gleamdb.Db) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)

  case wisp.path_segments(req) {
    ["admin", ..rest] ->
      case rest {
        ["login"] -> handle_login(req)
        _ -> {
          use <- require_admin(req)
          case rest {
            [] -> serve_editor(req)
            ["stats"] -> serve_stats(req, db)
            _ -> wisp.not_found()
          }
        }
      }
    ["health"] -> handle_health(db)
    ["static", ..file] -> serve_static(req, file)
    ["gleamcms_output", ..file] -> serve_output(req, file)
    ["sites"] -> serve_sites()
    ["api", ..rest] -> {
      use <- require_admin(req)
      case rest {
        ["posts"] -> handle_list_posts(db)
        ["publish"] -> handle_publish(req, db)
        ["facts", "sync"] -> handle_sync(req, db)
        ["generate"] -> handle_generate(req, db)
        ["ai", "design"] -> handle_ai_design(req, db)
        _ -> wisp.not_found()
      }
    }
    _ -> serve_home(req)
  }
}

fn require_admin(req: Request, handler: fn() -> Response) -> Response {
  let bearer = list.key_find(req.headers, "authorization")
  let cookie = list.key_find(req.headers, "cookie")
  let has_cookie = case cookie {
    Ok(c) -> string.contains(c, "gleamcms_token=sovereign-token-2026")
    Error(_) -> False
  }
  case bearer, has_cookie {
    Ok("Bearer sovereign-token-2026"), _ -> handler()
    _, True -> handler()
    _, _ ->
      wisp.redirect("/admin/login")
  }
}

fn handle_login(req: Request) -> Response {
  case req.method {
    http.Post -> {
      use body <- wisp.require_string_body(req)
      let token = case string.split(body, "token=") {
        [_, t, ..] -> string.trim(t)
        _ -> ""
      }
      case token {
        "sovereign-token-2026" ->
          wisp.redirect("/admin")
          |> wisp.set_header("set-cookie", "gleamcms_token=sovereign-token-2026; Path=/; HttpOnly; SameSite=Strict")
        _ ->
          wisp.response(200)
          |> wisp.html_body(login_page("Invalid token. Try again."))
      }
    }
    _ -> {
      // Check for ?token= in the query string for one-click link login
      let token_param =
        wisp.get_query(req)
        |> list.key_find("token")
        |> result.unwrap("")
      case token_param {
        "sovereign-token-2026" ->
          wisp.redirect("/admin")
          |> wisp.set_header("set-cookie", "gleamcms_token=sovereign-token-2026; Path=/; HttpOnly; SameSite=Strict")
        _ ->
          wisp.response(200)
          |> wisp.html_body(login_page(""))
      }
    }
  }
}

fn login_page(error: String) -> String {
  let err_html = case error {
    "" -> ""
    msg -> "<p style='color:#f87171;margin-bottom:1rem'>" <> msg <> "</p>"
  }
  "<!DOCTYPE html>
<html lang=\"en\"><head>
  <meta charset=\"UTF-8\">
  <title>GleamCMS Login</title>
  <style>
    :root{--bg:#0f172a;--card:rgba(255,255,255,0.05);--accent:#3b82f6;--text:#f8fafc}
    body{font-family:monospace;background:var(--bg);color:var(--text);display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
    .card{background:var(--card);border:1px solid rgba(255,255,255,0.1);border-radius:16px;padding:2.5rem;min-width:320px;text-align:center}
    h2{margin-bottom:1.5rem}input{width:100%;box-sizing:border-box;padding:.75rem 1rem;border-radius:8px;border:1px solid #334155;background:#1e293b;color:var(--text);font-family:monospace;margin-bottom:1rem}
    button{width:100%;padding:.75rem;background:var(--accent);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:1rem}
  </style>
</head><body>
  <div class=\"card\">
    <h2>GleamCMS Login</h2>
    " <> err_html <> "
    <form method=\"POST\" action=\"/admin/login\">
      <input type=\"password\" name=\"token\" placeholder=\"Bearer Token\" autofocus>
      <button type=\"submit\">Enter Admin</button>
    </form>
  </div>
</body></html>"
}

fn serve_static(req: Request, _file: List(String)) -> Response {
  let assert Ok(priv) = wisp.priv_directory("gleamdb")
  use <- wisp.serve_static(req, under: "/static", from: priv <> "/static/gleamcms")
  wisp.not_found()
}

fn serve_output(req: Request, _file: List(String)) -> Response {
  // Use absolute path for robustness
  use <- wisp.serve_static(req, under: "/gleamcms_output", from: "/Users/brixelectronics/Documents/mac/gswarm/gleamcms_output")
  wisp.not_found()
}

fn serve_home(_req: Request) -> Response {
  let html = "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>GleamCMS - Sovereign Content</title>
  <style>
    :root { --bg: #0f172a; --text: #f8fafc; --accent: #3b82f6; }
    body { font-family: 'Inter', sans-serif; background: var(--bg); color: var(--text); margin: 0; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
    .card { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 16px; padding: 3rem; max-width: 500px; text-align: center; backdrop-filter: blur(12px); }
    h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
    h1 span { color: var(--accent); }
    p { opacity: 0.7; margin-bottom: 2rem; }
    a { display: inline-block; background: var(--accent); color: #fff; text-decoration: none; padding: 0.75rem 1.5rem; border-radius: 8px; font-weight: 600; margin: 0.25rem; }
    a.ghost { background: transparent; border: 1px solid var(--accent); color: var(--accent); }
    .status { margin-top: 2rem; font-size: 0.8rem; opacity: 0.4; }
  </style>
</head>
<body>
  <div class=\"card\">
    <h1>Gleam<span>CMS</span></h1>
    <p>A Fact-Oriented, Sovereign Content Management System built on GleamDB v2.1.0.</p>
    <a href=\"/admin\">Admin Editor</a>
    <a class=\"ghost\" href=\"/health\">Health Check</a>
    <div class=\"status\">⚡ 50 Themes &bull; CAS Media &bull; Datalog Engine</div>
  </div>
</body>
</html>"
  wisp.ok()
  |> wisp.html_body(html)
}

fn serve_editor(_req: Request) -> Response {
  let html = editor.render()
  wisp.ok()
  |> wisp.html_body(html)
}

fn handle_health(db: gleamdb.Db) -> Response {
  // Diagnostic query: Ensure we can query the engine
  let q = [gleamdb.p(#(Var("_"), "cms.post/id", Var("_")))]
  case gleamdb.query(db, q) {
    _ -> {
      wisp.ok()
      |> wisp.json_body("{\"status\": \"healthy\", \"engine\": \"v2.1.0\"}")
    }
  }
}

fn serve_stats(_req: Request, db: gleamdb.Db) -> Response {
  // Leverage v1.9.0 Distributed Aggregates (Count posts)
  let q = [
    gleamdb.p(#(Var("e"), "cms.post/id", Var("id"))),
  ]
  let res = gleamdb.query(db, q)
  let count = list.length(res.rows)
  
  wisp.ok()
  |> wisp.html_body("<h1>CMS Stats</h1><p>Total Posts: " <> int.to_string(count) <> "</p>")
}

fn handle_publish(req: Request, db: gleamdb.Db) -> Response {
  case req.method {
    http.Post -> {
        use body <- wisp.require_string_body(req)
        case json.parse(body, publish_request_decoder()) {
          Ok(pub_req) -> {
            let p = post.new_post(
              pub_req.slug,
              pub_req.title,
              pub_req.slug,
              pub_req.content,
            )
            |> post.with_status(Published)
            
            case post.save_post(db, p) {
              Ok(_) -> {
                logging.log(logging.Info, "Published post: " <> pub_req.slug)
                wisp.ok()
                |> wisp.json_body("{\"status\": \"ok\"}")
              }
              Error(errors) -> {
                logging.log(logging.Warning, "Publication failed: " <> pub_req.slug)
                let error_msg = list.first(errors) |> result.unwrap("")
                wisp.bad_request("Validation failed: " <> error_msg)
              }
            }
          }
          Error(_) -> wisp.bad_request("Invalid JSON")
        }
    }
    _ -> wisp.method_not_allowed([http.Post])
  }
}

fn handle_generate(req: Request, db: gleamdb.Db) -> Response {
  case req.method {
    http.Post -> {
      let theme_param =
        wisp.get_query(req)
        |> list.key_find("theme")
        |> result.unwrap("Default Dark")

      logging.log(logging.Info, "Generate site: theme=" <> theme_param)

      let reports = case theme_param {
        "all" -> generator.build_all(db)
        "showcase" -> {
          let _ = generator.seed_showcase_posts(db)
          generator.build_showcase(db)
        }
        name -> [generator.build(db, name)]
      }

      let total_pages = list.fold(reports, 0, fn(acc, r) { acc + r.pages_written })
      let total_errors = list.fold(reports, 0, fn(acc, r) { acc + list.length(r.errors) })
      let sites_built = list.length(reports)

      logging.log(logging.Info, "Build complete: " <> int.to_string(total_pages) <> " pages across " <> int.to_string(sites_built) <> " sites")

      let body =
        "{\"status\": \"ok\", \"sites\": "
        <> int.to_string(sites_built)
        <> ", \"pages\": "
        <> int.to_string(total_pages)
        <> ", \"errors\": "
        <> int.to_string(total_errors)
        <> "}"

      wisp.ok()
      |> wisp.json_body(body)
    }
    _ -> wisp.method_not_allowed([http.Post])
  }
}

fn handle_ai_design(req: Request, db: gleamdb.Db) -> Response {
  case req.method {
    http.Post -> {
      use body <- wisp.require_string_body(req)
      let prompt = case json.parse(from: body, using: {
        use p <- decode.field("prompt", decode.string)
        decode.success(p)
      }) {
        Ok(p) -> p
        Error(_) -> ""
      }

      case prompt {
        "" -> wisp.bad_request("Missing prompt")
        _ -> {
          let project_id = designer.get_env("GOOGLE_PROJECT_ID") |> result.unwrap("")
          let bearer_token = designer.get_env("GOOGLE_BEARER_TOKEN") |> result.unwrap("")

          case project_id, bearer_token {
            "", _ -> wisp.internal_server_error() |> wisp.json_body("{\"error\": \"GOOGLE_PROJECT_ID not set\"}")
            _, "" -> wisp.internal_server_error() |> wisp.json_body("{\"error\": \"GOOGLE_BEARER_TOKEN not set\"}")
            pid, token -> {
              case designer.design_theme(prompt, pid, token) {
                Ok(config) -> {
                  // Manifest sections as facts in the database
                  // We use a specific slug prefix for thematic sections with indices for order
                  let _ = list.index_map(config.sections, fn(sec, i) {
                    let section_slug = 
                      string.lowercase(string.replace(config.name, " ", "-")) 
                      <> "-" <> int.to_string(i + 1) 
                      <> "-" <> string.replace(sec.section_type, " ", "-")
                      
                    wisp.log_info("Saving section: " <> section_slug)
                    let p = post.new_post(
                      section_slug,
                      sec.title,
                      section_slug,
                      sec.content,
                    )
                    |> post.with_status(post.Published)
                    |> post.with_section_type(sec.section_type)
                    
                    post.save_post(db, p)
                  })

                  let resp = json.object([
                    #("name", json.string(config.name)),
                    #("bg_color", json.string(config.bg_color)),
                    #("text_color", json.string(config.text_color)),
                    #("accent_color", json.string(config.accent_color)),
                    #("border_color", json.string(config.border_color)),
                    #("card_bg", json.string(config.card_bg)),
                    #("font_family", json.string(config.font_family)),
                    #("layout_style", json.string(config.layout_style)),
                    #("shadow_depth", json.string(config.shadow_depth)),
                    #("border_radius", json.string(config.border_radius)),
                    #("spacing_scale", json.string(config.spacing_scale)),
                    #("custom_flourish", json.string(config.custom_flourish)),
                  ]) |> json.to_string
                  wisp.ok() |> wisp.json_body(resp)
                }
                Error(e) -> wisp.internal_server_error() |> wisp.json_body("{\"error\": \"" <> e <> "\"}")
              }
            }
          }
        }
      }
    }
    _ -> wisp.method_not_allowed([http.Post])
  }
}

fn serve_sites() -> Response {
  let sites = generator.list_generated()
  let cards = list.map(sites, fn(slug) {
    "<a class=\"site-card\" href=\"/gleamcms_output/" <> slug <> "/index.html\">"
    <> "<div class=\"site-name\">" <> slug <> "</div>"
    <> "<div class=\"site-links\">"
    <> "<span>index</span> · <span>rss</span>"
    <> "</div></a>"
  })
  let body = case sites {
    [] -> "<p style='color:#94a3b8'>No sites generated yet. Use <code>POST /api/generate</code> first.</p>"
    _ -> string.join(cards, "\n")
  }
  let html = "
<!DOCTYPE html><html lang=\"en\"><head>
  <meta charset=\"UTF-8\">
  <title>GleamCMS — Generated Sites</title>
  <style>
    :root{--bg:#0f172a;--card:rgba(255,255,255,0.05);--accent:#3b82f6;--text:#f8fafc}
    body{font-family:monospace;background:var(--bg);color:var(--text);padding:2rem;margin:0}
    h1{margin-bottom:2rem}a{color:inherit;text-decoration:none}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:1rem}
    .site-card{background:var(--card);border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:1.25rem;transition:border-color .2s,transform .2s;display:block}
    .site-card:hover{border-color:var(--accent);transform:translateY(-2px)}
    .site-name{font-weight:700;font-size:0.95rem;margin-bottom:0.5rem;color:var(--text)}
    .site-links{color:#64748b;font-size:0.8rem}
    .back{margin-bottom:1.5rem;display:inline-block;color:#64748b;font-size:0.85rem}
    .back:hover{color:var(--accent)}
  </style>
</head><body>
  <a class=\"back\" href=\"/admin/login?token=sovereign-token-2026\">← back to editor</a>
  <h1>🌐 Generated Sites</h1>
  <div class=\"grid\">" <> body <> "</div>
</body></html>"
  wisp.ok()
  |> wisp.html_body(html)
}
fn handle_sync(req: Request, db: gleamdb.Db) -> Response {
  case req.method {
    http.Post -> {
        use body <- wisp.require_string_body(req)
        case json.parse(body, decode.list(sync_fact_decoder())) {
          Ok(facts) -> {
            let facts = list.map(facts, fn(f) {
              let f: SyncFact = f
              #(fact.deterministic_uid(f.eid), f.attr, fact.Str(f.val))
            })
            let _ = gleamdb.transact(db, facts)
            wisp.ok()
            |> wisp.json_body("{\"status\": \"synced\"}")
          }
          Error(_) -> wisp.bad_request("Invalid Fact Sync Batch")
        }
    }
    _ -> wisp.method_not_allowed([http.Post])
  }
}
fn handle_list_posts(db: gleamdb.Db) -> Response {
  let posts = post.get_all_published(db)
  let json_posts = json.array(posts, fn(p) {
    json.object([
      #("id", json.string(post.get_id(p))),
      #("title", json.string(post.get_title(p))),
      #("slug", json.string(post.get_slug(p))),
      #("section_type", json.string(post.get_section_type(p))),
    ])
  })
  let resp = json.to_string(json_posts)
  wisp.ok() |> wisp.json_body(resp)
}
