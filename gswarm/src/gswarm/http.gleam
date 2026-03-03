import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request as HttpRequest}
import gleam/http/response.{type Response as HttpResponse} as http_response
import gleam/bytes_tree
import gleam/json
import gleam/list
import gleam/dict
import gleam/result
import gleam/string
import gleam/int
import gleam/float
import mist
import gswarm/node.{type ShardedContext}
import gswarm/leaderboard
import gswarm/amka_domain
import gswarm/insider_store
import gswarm/console
import gswarm/correlator
import gswarm/rate_limiter
import gleam/order
import gleamdb
import gleamdb/fact
import gleamdb/shared/types

// We need to inject the leaderboard actor into the context
// The `ShardedContext` doesn't strictly have it, but we can access it via a registry or
// we can pass it to `start_server`.
// For now, let's modify `start_server` to take the leaderboard actor.

pub fn start_server(
  port: Int, 
  ctx: ShardedContext, 
  lb_actor: Subject(leaderboard.Message),
  insider_actor: Subject(insider_store.Message),
  limiter_actor: Subject(rate_limiter.Message)
) {
  // Define the handler
  let handler = fn(req: HttpRequest(mist.Connection)) -> HttpResponse(mist.ResponseData) {
    handle_request(req, ctx, lb_actor, insider_actor, limiter_actor)
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(port)
    |> mist.start

  Nil
}

fn handle_request(
  req: HttpRequest(mist.Connection), 
  ctx: node.ShardedContext, 
  lb: Subject(leaderboard.Message),
  insider: Subject(insider_store.Message),
  limiter: Subject(rate_limiter.Message)
) -> HttpResponse(mist.ResponseData) {
  // 0. Rate Limiting Middleware
  let ip = "0.0.0.0" // Placeholder until mist provides IP in Req
  let reply = process.new_subject()
  process.send(limiter, rate_limiter.Check(ip, reply))
  case process.receive(reply, 100) {
    Ok(True) -> {
      case request.path_segments(req) {
    [] -> home_page(ctx, lb, insider)
    ["leaderboard"] -> leaderboard_page(lb, insider)
    ["trader", address] -> trader_detail_page(lb, address)
    ["console"] -> console_page()
    ["api", "graph"] -> graph_api(ctx, lb, insider)
    ["api", "health"] -> health_api(ctx)
    ["api", "insiders"] -> insiders_api(ctx)
    ["api", "leaderboard"] -> leaderboard_api(lb, insider)
    ["api", "trader", address, "history"] -> trader_history_api(lb, address)
    ["metrics"] -> metrics_api(ctx)
    ["api", "trader", _address, "related"] -> {
      http_response.Response(200, [], mist.Bytes(bytes_tree.from_string("[]")))
    }
    ["api", "trader", _address, "profile"] -> {
      http_response.Response(404, [], mist.Bytes(bytes_tree.from_string("Not Found")))
    }
    _ -> not_found()
      }
    }
    _ -> {
       http_response.new(429)
       |> http_response.set_body(mist.Bytes(bytes_tree.from_string("Too Many Requests")))
    }
  }
}

fn html_response(html: String) -> HttpResponse(mist.ResponseData) {
  hue_response(200, html, "text/html")
}

fn json_response(json_str: String) -> HttpResponse(mist.ResponseData) {
  hue_response(200, json_str, "application/json")
}

fn hue_response(status: Int, body: String, content_type: String) -> HttpResponse(mist.ResponseData) {
  http_response.new(status)
  |> http_response.set_header("content-type", content_type)
  |> http_response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn not_found() -> HttpResponse(mist.ResponseData) {
  http_response.new(404)
  |> http_response.set_body(mist.Bytes(bytes_tree.from_string("Not Found")))
}

fn internal_server_error() -> HttpResponse(mist.ResponseData) {
  http_response.new(500)
  |> http_response.set_body(mist.Bytes(bytes_tree.from_string("Internal Server Error")))
}
fn console_page() -> HttpResponse(mist.ResponseData) {
  html_response(console.html())
}

fn graph_api(
  ctx: node.ShardedContext,
  lb: Subject(leaderboard.Message),
  _insider: Subject(insider_store.Message)
) -> HttpResponse(mist.ResponseData) {
  // 1. Cluster & Shards
  let cluster_node = json.object([
    #("id", json.string(ctx.cluster_id)),
    #("type", json.string("cluster")),
    #("label", json.string("Gswarm Hive"))
  ])
  
  let shards = dict.keys(ctx.db.shards) |> list.sort(int.compare)
  let shard_nodes = list.map(shards, fn(id) {
    let sid = "Shard " <> int.to_string(id)
    json.object([
      #("id", json.string(sid)),
      #("type", json.string("shard")),
      #("label", json.string(sid))
    ])
  })
  
  let shard_links = list.map(shards, fn(id) {
    json.object([
      #("source", json.string(ctx.cluster_id)),
      #("target", json.string("Shard " <> int.to_string(id)))
    ])
  })

  let reply = process.new_subject()
  process.send(lb, leaderboard.GetTopStats(100, reply))
  let traders = process.receive(reply, 1000) |> result.unwrap([])
  
  // Phase 10: Fetch Behavioral Clusters from DB
  let assert Ok(primary_db) = dict.get(ctx.db.shards, 0)
  let cluster_query = [
    types.Positive(#(types.Var("t"), "trader/behavioral_tag", types.Var("tag")))
  ]
  let cluster_results = gleamdb.query(primary_db, cluster_query).rows
  let cluster_map = list.fold(cluster_results, dict.new(), fn(acc, row) {
    case dict.get(row, "t"), dict.get(row, "tag") {
        Ok(fact.Ref(fact.EntityId(id))), Ok(fact.Str(tag)) -> {
            dict.insert(acc, id, tag)
        }
        _, _ -> acc
    }
  })
  
  let trader_nodes = list.map(traders, fn(t) {
    let tid_int = fact.phash2(t.trader_id)
    let cluster = dict.get(cluster_map, tid_int) |> result.unwrap("Unknown")
    json.object([
      #("id", json.string(t.trader_id)),
      #("type", json.string("trader")),
      #("label", json.string(string.slice(t.trader_id, 0, 6) <> "...")),
      #("alpha", json.float(t.total_pnl)),
      #("cluster", json.string(cluster))
    ])
  })
  
  // 3. Mirror Shard (Phase 11)
  let mirror_node = json.object([
    #("id", json.string("Mirror Shard")),
    #("type", json.string("mirror")),
    #("label", json.string("Speculative Mirror"))
  ])
  
  // Link Institutional Insiders to Mirror Shard
  let mirror_links = list.filter_map(traders, fn(t) {
    let tid_int = fact.phash2(t.trader_id)
    case dict.get(cluster_map, tid_int) {
        Ok("Institutional Insider") -> Ok(json.object([
            #("source", json.string(t.trader_id)),
            #("target", json.string("Mirror Shard")),
            #("type", json.string("mirror_link"))
        ]))
        _ -> Error(Nil)
    }
  })

  // Link traders to cluster
  let trader_links = list.map(traders, fn(t) {
    json.object([
      #("source", json.string(ctx.cluster_id)),
      #("target", json.string(t.trader_id))
    ])
  })

  let all_nodes = list.flatten([[cluster_node, mirror_node], shard_nodes, trader_nodes])
  let all_links = list.flatten([shard_links, trader_links, mirror_links])
  
  let graph_json = json.object([
    #("nodes", json.preprocessed_array(all_nodes)),
    #("links", json.preprocessed_array(all_links))
  ])
  
  json_response(json.to_string(graph_json))
}

fn insiders_api(ctx: node.ShardedContext) -> HttpResponse(mist.ResponseData) {
  let assert Ok(primary_db) = dict.get(ctx.db.shards, 0)
  let insiders = correlator.detect_insider_patterns(primary_db)
  let json_data = json.array(insiders, json.string)
  json_response(json.to_string(json_data))
}

fn health_api(ctx: node.ShardedContext) -> HttpResponse(mist.ResponseData) {
  // Placeholder uptime/memory
  let json_data = json.object([
    #("status", json.string("active")),
    #("shard_count", json.int(dict.size(ctx.db.shards))),
    #("memory_mb", json.int(128)), // Mock
    #("uptime_sec", json.int(3600)) // Mock
  ])
  json_response(json.to_string(json_data))
}

fn leaderboard_api(
  lb: Subject(leaderboard.Message),
  _insider: Subject(insider_store.Message)
) -> HttpResponse(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(lb, leaderboard.GetTopStats(100, reply))
  
  let traders = process.receive(reply, 1000) |> result.unwrap([])
    |> list.sort(fn(a, b) { float.compare(b.total_pnl, a.total_pnl) })
    |> list.take(10)
    
  let trader_objs = list.map(traders, fn(t) {
    json.object([
      #("id", json.string(t.trader_id)),
      #("alpha", json.float(t.total_pnl))
    ])
  })
  
  let json_data = json.object([
    #("traders", json.preprocessed_array(trader_objs))
  ])
  
  json_response(json.to_string(json_data))
}



// --- Page Handlers (Ported from amkabot/web.gleam) ---

fn home_page(
  ctx: node.ShardedContext, 
  lb: Subject(leaderboard.Message),
  insider: Subject(insider_store.Message)
) -> HttpResponse(mist.ResponseData) {
  // 1. Fetch Leaderboard Stats
  let reply = process.new_subject()
  process.send(lb, leaderboard.GetTopStats(100, reply))

  // Fetch Insider Stats
  let insider_reply = process.new_subject()
  process.send(insider, insider_store.GetAllInsiders(insider_reply))
  let insiders = process.receive(insider_reply, 2000) |> result.unwrap([])
  let insider_map = list.map(insiders, fn(i) { #(i.trader_id, i) }) |> dict.from_list

  let trader_stats: List(leaderboard.Stats) =
    process.receive(reply, 2000)
    |> result.unwrap([])
    |> list.sort(fn(a: leaderboard.Stats, b: leaderboard.Stats) {
      float.compare(b.total_pnl, a.total_pnl)
    })

  let lb_rows =
    list.map(trader_stats, fn(s: leaderboard.Stats) {
      let pnl_color = case s.total_pnl >=. 0.0 {
        True -> "#10b981"
        _ -> "#ef4444"
      }

      let formatted_pnl =
        { s.total_pnl *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string

      let insider_badge = case dict.get(insider_map, s.trader_id) {
          Ok(i) if i.confidence_score >. 0.7 -> "<span class=\"badge\" style=\"background: rgba(245, 158, 11, 0.1); color: #f59e0b; border-color: rgba(245, 158, 11, 0.2); margin-left: 0.5rem;\">INSIDER " <> float.to_string(i.confidence_score *. 100.0) <> "%</span>"
          _ -> ""
      }

      "<tr>
        <td style=\"font-family: monospace; color: #94a3b8;\">
            <a href=\"/trader/" <> s.trader_id <> "\" style=\"color: inherit; text-decoration: none;\">" <> s.trader_id <> "</a>
            " <> insider_badge <> "
        </td>
        <td style=\"color: " <> pnl_color <> "; font-weight: bold;\">$" <> formatted_pnl <> "</td>
        <td>" <> int.to_string(s.prediction_count) <> "</td>
      </tr>"
    })
    |> string.join("")

  // 2. System Metrics
  let shard_count = dict.size(ctx.db.shards)
  
  let html =
    "
    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
        <title>Gswarm Hive Dashboard</title>
        <link href=\"https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&family=Inter:wght@400;600&display=swap\" rel=\"stylesheet\">
        <style>
            :root {
                --bg: #030712;
                --card-bg: rgba(17, 24, 39, 0.7);
                --border: rgba(255, 255, 255, 0.08);
                --gold: #f59e0b;
                --gold-glow: rgba(245, 158, 11, 0.2);
                --accent: #3b82f6;
            }
            body { 
                font-family: 'Inter', system-ui, sans-serif; 
                background-color: var(--bg); 
                color: #f8fafc; 
                margin: 0; 
                padding: 2rem;
                background-image: 
                    radial-gradient(circle at 0% 0%, rgba(59, 130, 246, 0.1) 0%, transparent 50%),
                    radial-gradient(circle at 100% 100%, rgba(245, 158, 11, 0.1) 0%, transparent 50%);
                min-height: 100vh;
            }
            .container { max-width: 1200px; margin: 0 auto; }
            
            header { 
                display: flex; 
                justify-content: space-between; 
                align-items: center; 
                margin-bottom: 3rem;
                padding-bottom: 1.5rem;
                border-bottom: 1px solid var(--border);
            }
            
            .logo-section h1 { 
                font-family: 'Outfit', sans-serif;
                font-size: 2.5rem; 
                margin: 0; 
                background: linear-gradient(135deg, #fff 0%, #94a3b8 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                font-weight: 800;
                letter-spacing: -0.02em;
            }
            .logo-section span { color: var(--gold); font-weight: 400; font-size: 1rem; letter-spacing: 0.1em; text-transform: uppercase; }

            .stats-overview { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1.5rem; margin-bottom: 3rem; }
            .stat-card { 
                background: var(--card-bg); 
                backdrop-filter: blur(12px);
                border: 1px solid var(--border);
                padding: 1.5rem; 
                border-radius: 1rem; 
                box-shadow: 0 10px 30px rgba(0,0,0,0.3);
                transition: transform 0.2s;
            }
            .stat-card:hover { transform: translateY(-5px); border-color: rgba(245, 158, 11, 0.3); }
            .stat-label { color: #64748b; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.5rem; }
            .stat-value { font-family: 'Outfit', sans-serif; font-size: 1.75rem; font-weight: 600; color: #f1f5f9; }
            .stat-value.gold { color: var(--gold); }

            .main-grid { display: grid; grid-template-columns: 1fr; gap: 2rem; }
            
            .section-card {
                background: var(--card-bg);
                backdrop-filter: blur(12px);
                border: 1px solid var(--border);
                border-radius: 1.25rem;
                overflow: hidden;
            }
            .section-header { 
                padding: 1.5rem 2rem; 
                border-bottom: 1px solid var(--border);
                display: flex;
                justify-content: space-between;
                align-items: center;
                background: rgba(255, 255, 255, 0.02);
            }
            .section-header h2 { 
                font-family: 'Outfit', sans-serif;
                font-size: 1.25rem; 
                margin: 0; 
                font-weight: 600;
            }
            
            table { width: 100%; border-collapse: collapse; }
            th { text-align: left; padding: 1rem 2rem; color: #475569; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.1em; background: rgba(0,0,0,0.2); }
            td { padding: 1rem 2rem; border-bottom: 1px solid var(--border); font-size: 0.95rem; }
            tr:hover td { background: rgba(255, 255, 255, 0.02); }
            tr:last-child td { border-bottom: none; }
            
            .badge { 
                display: inline-flex; 
                align-items: center; 
                padding: 0.25rem 0.75rem; 
                border-radius: 9999px; 
                font-size: 0.7rem; 
                font-weight: 600; 
                text-transform: uppercase;
                background: rgba(16, 185, 129, 0.1);
                color: #10b981;
                border: 1px solid rgba(16, 185, 129, 0.2);
            }
            .pulse {
                width: 8px;
                height: 8px;
                background: #10b981;
                border-radius: 50%;
                margin-right: 8px;
                box-shadow: 0 0 10px #10b981;
                animation: pulse 2s infinite;
            }
            @keyframes pulse {
                0% { transform: scale(1); opacity: 1; }
                50% { transform: scale(1.5); opacity: 0.5; }
                100% { transform: scale(1); opacity: 1; }
            }
            
            a { color: inherit; text-decoration: none; transition: color 0.2s; }
            a:hover { color: var(--gold); }
        </style>
    </head>
    <body>
        <div class=\"container\">
            <header>
                <div class=\"logo-section\">
                    <span>Sovereign Fabric</span>
                    <h1>GSWARM 🐝</h1>
                </div>
                <div class=\"badge\">
                    <div class=\"pulse\"></div>
                    Fabric Active
                </div>
            </header>

            <div class=\"stats-overview\">
                <div class=\"stat-card\">
                    <div class=\"stat-label\">Cluster Identity</div>
                    <div class=\"stat-value\">" <> ctx.cluster_id <> "</div>
                </div>
                <div class=\"stat-card\">
                    <div class=\"stat-label\">Sovereign Shards</div>
                    <div class=\"stat-value gold\">" <> int.to_string(shard_count) <> "</div>
                </div>
                <div class=\"stat-card\">
                    <div class=\"stat-label\">Intelligence Units</div>
                    <div class=\"stat-value\">" <> int.to_string(list.length(trader_stats)) <> "</div>
                </div>
                <div class=\"stat-card\">
                    <div class=\"stat-label\">Network Status</div>
                    <div class=\"stat-value\" style=\"color: #10b981;\">Synchronized</div>
                </div>
            </div>

            <div class=\"main-grid\">
                <div class=\"section-card\">
                    <div class=\"section-header\">
                        <h2>Hive Intelligence Leaderboard</h2>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>Intelligence Unit (Trader)</th>
                                <th>Realized PnL</th>
                                <th>Predictions</th>
                            </tr>
                        </thead>
                        <tbody>
                            " <> lb_rows <> "
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </body>
    </html>
  "
  html_response(html)
}

fn leaderboard_page(
  lb: Subject(leaderboard.Message),
  insider: Subject(insider_store.Message)
) -> HttpResponse(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(lb, leaderboard.GetTopStats(100, reply))

  let insider_reply = process.new_subject()
  process.send(insider, insider_store.GetAllInsiders(insider_reply))
  let insiders = process.receive(insider_reply, 1000) |> result.unwrap([])

  let trader_stats: List(leaderboard.Stats) =
    process.receive(reply, 2000)
    |> result.unwrap([])
    |> list.sort(fn(a: leaderboard.Stats, b: leaderboard.Stats) {
      let a_conf = list.find(insiders, fn(i) { i.trader_id == a.trader_id }) |> result.map(fn(i) { i.confidence_score }) |> result.unwrap(0.0)
      let b_conf = list.find(insiders, fn(i) { i.trader_id == b.trader_id }) |> result.map(fn(i) { i.confidence_score }) |> result.unwrap(0.0)
      
      case float.compare(b_conf, a_conf) {
        order.Eq -> float.compare(b.total_pnl, a.total_pnl)
        other -> other
      }
    })

  let rows =
    list.map(trader_stats, fn(s: leaderboard.Stats) {
      let pnl_color = case s.total_pnl >=. 0.0 {
        True -> "#10b981"
        _ -> "#ef4444"
      }

      let calibration = case s.prediction_count > 0 {
        True -> s.calibration_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }

      let confidence = list.find(insiders, fn(i) { i.trader_id == s.trader_id }) |> result.map(fn(i) { i.confidence_score }) |> result.unwrap(0.0)
      let formatted_conf = { confidence *. 100.0 |> float.round |> int.to_float } /. 100.0 |> float.to_string

      let formatted_pnl =
        { s.total_pnl *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_roi =
        { s.roi *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_calib =
        { calibration *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string

      "<tr id=\"trader-" <> s.trader_id <> "\">
      <td style=\"font-family: monospace; color: #94a3b8;\"><a href=\"/trader/" <> s.trader_id <> "\" style=\"color: inherit; text-decoration: none;\">" <> s.trader_id <> "</a></td>
      <td class=\"pnl\" style=\"color: " <> pnl_color <> "; font-weight: bold;\">$" <> formatted_pnl <> "</td>
      <td class=\"roi\">" <> formatted_roi <> "%</td>
      <td class=\"calib\">" <> formatted_calib <> "</td>
      <td class=\"preds\">" <> int.to_string(s.prediction_count) <> "</td>
      <td class=\"insider\" style=\"color: #f59e0b; font-weight: bold;\">" <> formatted_conf <> "</td>
    </tr>"
    })
    |> list.fold("", fn(acc, row) { acc <> row })

  let html = "
    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <title>Hive Leaderboard | Gswarm</title>
        <style>
            body { font-family: 'Inter', system-ui, sans-serif; background: #000; color: #f8fafc; margin: 0; padding: 2rem; }
            .container { max-width: 1000px; margin: 0 auto; }
            h1 { font-size: 2rem; margin-bottom: 2rem; border-left: 4px solid #f59e0b; padding-left: 1rem; color: #ddd; }
            table { width: 100%; border-collapse: collapse; background: #111; border-radius: 0.75rem; overflow: hidden; border: 1px solid #222; }
            th { text-align: left; padding: 1rem; background: #222; color: #888; font-size: 0.875rem; text-transform: uppercase; letter-spacing: 0.05em; }
            td { padding: 1rem; border-bottom: 1px solid #222; }
            tr:last-child td { border-bottom: none; }
            a:hover { text-decoration: underline !important; }
            .back-link { display: inline-block; margin-top: 1.5rem; color: #555; text-decoration: none; font-size: 0.875rem; }
            .back-link:hover { color: #888; }
        </style>
    </head>
    <body>
        <div class=\"container\">
            <h1>Hive Mind Leaderboard <span id=\"status\" style=\"font-size: 0.8rem; color: #10b981;\">● Live</span></h1>
            <table>
                <thead>
                    <tr>
                        <th>Trader Address</th>
                        <th>Realized PnL</th>
                        <th>ROI (Est.)</th>
                        <th>Calibration</th>
                        <th>Resolved Preds</th>
                        <th>Confidence</th>
                    </tr>
                </thead>
                <tbody id=\"leaderboard-body\">
                    " <> rows <> "
                </tbody>
            </table>
            <a href=\"/\" class=\"back-link\">← Back to Analytics Overview</a>
        </div>
    </body>
    </html>
  "

  html_response(html)
}

fn trader_detail_page(lb: Subject(leaderboard.Message), address: String) -> HttpResponse(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(lb, leaderboard.GetStats(address, reply))

  let stats_result =
    process.receive(reply, 2000)
    |> result.flatten

  case stats_result {
    Ok(s) -> {
      let pnl_color = case s.total_pnl >=. 0.0 {
        True -> "#10b981"
        _ -> "#ef4444"
      }
      let calib_score = case s.prediction_count > 0 {
        True -> s.calibration_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }
      let sharp_score = case s.prediction_count > 0 {
        True -> s.sharpness_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }
      let formatted_pnl =
        { s.total_pnl *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_roi =
        { s.roi *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_calib =
        { calib_score *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_sharp =
        { sharp_score *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string

      // Fetch historical data from Actor (Snapshots + Activity)
      let reply_hist = process.new_subject()
      process.send(lb, leaderboard.GetHistory(address, reply_hist))
      let #(history_snaps, history_activities) =
        process.receive(reply_hist, 2000)
        |> result.unwrap(Ok(#([], [])))
        |> result.unwrap(#([], []))

      let history_rows = render_activity_rows(history_activities)
      let sparkline_svg = generate_sparkline(history_snaps)

      let html = "
            <!DOCTYPE html>
            <html lang=\"en\">
            <head>
                <meta charset=\"UTF-8\">
                <title>Trader Detail | Gswarm</title>
                <style>
                    body { font-family: 'Inter', system-ui, sans-serif; background: #000; color: #f8fafc; padding: 4rem; }
                    .container { max-width: 850px; margin: 0 auto; background: #111; padding: 3rem; border-radius: 1rem; border: 1px solid #222; }
                    h1 { font-size: 1.2rem; color: #888; margin-bottom: 0.5rem; font-family: monospace; overflow-wrap: break-word; }
                    .value { font-size: 3rem; font-weight: 800; margin-bottom: 2rem; color: " <> pnl_color <> "; }
                    .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 2rem; border-top: 1px solid #222; padding-top: 2rem; margin-bottom: 3rem; }
                    .label { color: #555; font-size: 0.875rem; text-transform: uppercase; margin-bottom: 0.5rem; }
                    .stat { font-size: 1.5rem; font-weight: 600; }
                    .history-title { font-size: 1.25rem; font-weight: bold; margin-bottom: 1rem; border-bottom: 1px solid #222; padding-bottom: 0.5rem; display: flex; justify-content: space-between; align-items: center; }
                    .history-item { display: flex; justify-content: space-between; padding: 0.75rem 0; border-bottom: 1px solid #111; color: #ccc; font-size: 0.95rem; }
                    .history-item:last-child { border-bottom: none; }
                    .type-badge { padding: 0.25rem 0.5rem; border-radius: 0.25rem; font-size: 0.75rem; font-weight: bold; text-transform: uppercase; }
                    .BUY { background: #3b82f6; color: white; }
                    .SELL { background: #f59e0b; color: white; }
                    .REDEEM { background: #10b981; color: white; }
                    .back { display: block; margin-top: 3rem; color: #3b82f6; text-decoration: none; font-weight: 500; }
                    .sparkline-container { margin-bottom: 2rem; padding: 1rem; background: #050505; border-radius: 0.5rem; }
                </style>
            </head>
            <body>
                <div class=\"container\">
                    <h1>Trader: " <> s.trader_id <> "</h1>
                    <div class=\"value\">$" <> formatted_pnl <> " <span style=\"font-size: 1rem; font-weight: normal; color: #555;\">Realized PnL</span></div>
                    
                    <div class=\"grid\">
                        <div>
                            <div class=\"label\">ROI (Est.)</div>
                            <div class=\"stat\">" <> formatted_roi <> "%</div>
                        </div>
                        <div>
                            <div class=\"label\">Calibration Score</div>
                            <div class=\"stat\">" <> formatted_calib <> "</div>
                        </div>
                        <div>
                            <div class=\"label\">Sharpness Score</div>
                            <div class=\"stat\">" <> formatted_sharp <> "</div>
                        </div>
                        <div>
                            <div class=\"label\">Resolved Predictions</div>
                            <div class=\"stat\">" <> int.to_string(
          s.prediction_count,
        ) <> "</div>
                        </div>
                    </div>

                    <div class=\"sparkline-container\">
                        <div class=\"label\">Calibration Trend (90 Days)</div>
                        " <> sparkline_svg <> "
                    </div>

                    <div class=\"history\">
                        <div class=\"history-title\">
                            Historical Activity Feed
                            <a href=\"/api/trader/" <> address <> "/history\" style=\"font-size: 0.8rem; color: #3b82f6; text-decoration: none;\">JSON API</a>
                        </div>
                        " <> history_rows <> "
                    </div>
                    
                    <a href=\"/leaderboard\" class=\"back\">← Back to Leaderboard</a>
                </div>
            </body>
            </html>
        "
      html_response(html)
    }
    Error(_) -> not_found()
  }
}

fn trader_history_api(lb: Subject(leaderboard.Message), address: String) -> HttpResponse(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(lb, leaderboard.GetHistory(address, reply))

  let result = process.receive(reply, 2000)
  case result {
    Ok(Ok(#(history, _))) -> {
      let json_data =
        json.object([
          #("address", json.string(address)),
          #(
            "history",
            json.preprocessed_array(
              list.map(history, fn(h) {
                json.object([
                  #("date", json.string(h.date)),
                  #("calibration", json.float(h.calibration_score)),
                  #("sharpness", json.float(h.sharpness_score)),
                ])
              }),
            ),
          ),
        ])
      json_response(json.to_string(json_data))
    }
    _ -> internal_server_error()
  }
}

// Stubs for removed SQLite functions
// Removed unused stubs

fn metrics_api(ctx: node.ShardedContext) -> HttpResponse(mist.ResponseData) {
  let shard_count = dict.size(ctx.db.shards)
  let json_data = json.object([
    #("shard_count", json.int(shard_count)),
    #("hll_cardinality", json.int(100)), // Placeholder for HLL
    #("cluster_id", json.string(ctx.cluster_id))
  ])
  json_response(json.to_string(json_data))
}

fn render_activity_rows(activities: List(amka_domain.TradeActivity)) -> String {
  case list.length(activities) {
    0 -> "<div style=\"color: #64748b; font-style: italic; padding: 1rem;\">No recent activity recorded.</div>"
    _ -> {
      list.map(activities, fn(a) {
        let type_badge = string.uppercase(string.inspect(a.trade_type))
        "<div class=\"history-item\">
            <span><span class=\"type-badge " <> type_badge <> "\">" <> type_badge <> "</span> " <> a.market_slug <> "</span>
            <span style=\"color: #94a3b8;\">$" <> float.to_string(a.usdc_size) <> " @ " <> float.to_string(a.price) <> "</span>
        </div>"
      })
      |> string.join("")
    }
  }
}

fn generate_sparkline(data: List(leaderboard.TraderSnapshot)) -> String {
  case list.length(data) {
    0 ->
      "<div style=\"color: #64748b; font-style: italic; padding: 1rem;\">Not enough history for trend analysis.</div>"
    _ -> {
      let width = 800.0
      let height = 100.0
      let count = list.length(data)
      let step_x = width /. int.to_float(int.max(1, count - 1))

      let points =
        list.index_map(data, fn(d, i) {
          let x = int.to_float(i) *. step_x
          let y = height -. { d.calibration_score *. height }
          float.to_string(x) <> "," <> float.to_string(y)
        })
        |> string.join(" ")

      "<svg width=\"100%\" height=\"100\" viewBox=\"0 0 800 100\" preserveAspectRatio=\"none\">
         <defs>
           <linearGradient id=\"grad\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">
             <stop offset=\"0%\" style=\"stop-color:#f59e0b;stop-opacity:1\" />
             <stop offset=\"100%\" style=\"stop-color:#f59e0b;stop-opacity:0.1\" />
           </linearGradient>
         </defs>
         <path d=\"M0,100 L"
      <> points
      <> " L800,100 Z\" fill=\"url(#grad)\" stroke=\"none\" />
         <polyline points=\""
      <> points
      <> "\" fill=\"none\" stroke=\"#f59e0b\" stroke-width=\"2\" />
       </svg>"
    }
  }
}
