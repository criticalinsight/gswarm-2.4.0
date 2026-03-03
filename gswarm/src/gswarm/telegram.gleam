import gleam/http/request
import gleam/http
import gleam/httpc
import gleam/json
import gleam/result
import gleam/string
import gleam/dynamic/decode

pub fn send_message(token: String, chat_id: String, text: String) -> Result(Nil, String) {
  let url = "https://api.telegram.org/bot" <> token <> "/sendMessage"
  
  let body = json.object([
    #("chat_id", json.string(chat_id)),
    #("text", json.string(text)),
    #("parse_mode", json.string("HTML"))
  ]) |> json.to_string()

  let assert Ok(req) = request.to(url)
  let req = req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)

  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> Ok(Nil)
    Ok(resp) -> Error("Telegram API Error: Status " <> string.inspect(resp.status) <> " | " <> resp.body)
    Error(e) -> Error("Network Error: " <> string.inspect(e))
  }
}
pub type Update {
  Update(id: Int, message: String, from: String)
}

pub fn get_updates(token: String, offset: Int) -> Result(List(Update), String) {
  let url = "https://api.telegram.org/bot" <> token <> "/getUpdates?offset=" <> string.inspect(offset)
  let assert Ok(req) = request.to(url)
  
  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> decode_updates(resp.body)
    _ -> Error("Failed to fetch updates")
  }
}

fn decode_updates(json_str: String) -> Result(List(Update), String) {
  let update_decoder = {
    use id <- decode.field("update_id", decode.int)
    use message <- decode.field("message", {
      use text <- decode.field("text", decode.string)
      use from <- decode.field("from", {
        use first_name <- decode.field("first_name", decode.string)
        decode.success(first_name)
      })
      decode.success(#(text, from))
    })
    decode.success(Update(id: id, message: message.0, from: message.1))
  }
  
  let root_decoder = {
    use result <- decode.field("result", decode.list(update_decoder))
    decode.success(result)
  }

  json.parse(from: json_str, using: root_decoder)
  |> result.map_error(fn(e) { "Failed to decode Telegram updates: " <> string.inspect(e) })
}

pub fn get_token() -> Result(String, String) {
  get_env("TELEGRAM_BOT_TOKEN")
  |> result.map_error(fn(_) { "TELEGRAM_BOT_TOKEN not set in environment" })
}

pub fn get_chat_id() -> Result(String, String) {
  get_env("TELEGRAM_CHAT_ID")
  |> result.map_error(fn(_) { "TELEGRAM_CHAT_ID not set in environment" })
}

@external(erlang, "gswarm_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
