import gleam/http/request
import gleam/http
import gleam/httpc
import gleam/json
import gleam/result
import gleam/list
import gleam/string
import gleam/dynamic/decode

const gemini_api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

pub fn assess_trader(nexus: String) -> Result(String, String) {
  case get_api_key() {
    Ok(key) -> {
      let url = gemini_api_url <> "?key=" <> key
      let body = json.object([
        #("contents", json.preprocessed_array([
          json.object([
            #("parts", json.preprocessed_array([
              json.object([#("text", json.string(build_prompt(nexus)))])
            ]))
          ])
        ])),
        #("tools", json.preprocessed_array([
          json.object([
            #("google_search", json.object([]))
          ])
        ]))
      ]) |> json.to_string()

      let assert Ok(req) = request.to(url)
      let req = req
        |> request.set_method(http.Post)
        |> request.set_header("content-type", "application/json")
        |> request.set_body(body)

      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> decode_gemini_response(resp.body)
        Ok(resp) -> Error("Gemini API Error: Status " <> string.inspect(resp.status) <> " | " <> resp.body)
        Error(e) -> Error("Network Error: " <> string.inspect(e))
      }
    }
    Error(_) -> Error("GEMINI_API_KEY not set in environment.")
  }
}

fn build_prompt(nexus: String) -> String {
  "You are the Gswarm Sovereign AI, an expert in financial forensics and predictive strategy.
  
  Analyze the following 'Trade Nexus' data. This includes trader performance and their recent trade history.
  
  CRITICAL: Use your GOOGLE SEARCH grounding tool to perform a forensic verification of the information environment for each trade timestamp (±30m window). 
  Look for specific catalyst events (headlines, social signals, sentiment shifts) that justify the trader's timing or position sizing.
  
  Your goal is to determine the 'Success Rationale':
  1. <b>Why is this trader winning?</b> Identify their specific edge based on the nexus and your search findings (e.g., info timing, momentum capture, contrarian value, or insider activity).
  2. <b>Signal Depth</b>: Do the trade timestamps relative to news suggest a significant information advantage?
  
  Provide a concise, high-utility report. Use <b>bold</b> for emphasis. DO NOT use Markdown symbols (*, _, #, [). Strictly use <b> and <i> tags.
  
  Nexus Data:
  " <> nexus
}

fn decode_gemini_response(json_str: String) -> Result(String, String) {
  let decoder = {
    use candidates <- decode.field("candidates", decode.list({
      use content <- decode.field("content", {
        use parts <- decode.field("parts", decode.list({
          use text <- decode.field("text", decode.string)
          decode.success(text)
        }))
        decode.success(parts)
      })
      decode.success(content)
    }))
    decode.success(candidates)
  }

  json.parse(from: json_str, using: decoder)
  |> result.map(fn(candidates) {
    case list.first(candidates) {
      Ok(parts) -> string.join(parts, "")
      _ -> "No assessment generated."
    }
  })
  |> result.map_error(fn(e) { "Failed to decode Gemini response: " <> string.inspect(e) })
}

fn get_api_key() -> Result(String, Nil) {
  get_env("GEMINI_API_KEY")
}

@external(erlang, "gswarm_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
