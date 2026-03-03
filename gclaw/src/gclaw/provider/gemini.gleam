import gleam/http/request
import gleam/http
import gleam/hackney
import gleam/json
import gleam/dynamic
import gleam/dynamic/decode
import gleam/string
import gleam/list
import gleam/dict.{type Dict}

pub type Message {
  Message(role: String, content: String)
}

pub type Tool {
  Tool(name: String, description: String, parameters: json.Json)
}

pub type ToolCall {
  ToolCall(name: String, args: Dict(String, dynamic.Dynamic))
}

pub type GeminiResponse {
  TextResponse(text: String)
  ToolCallResponse(calls: List(ToolCall))
}

pub fn generate(
  api_key: String,
  model: String,
  system_instruction: String,
  messages: List(Message),
  tools: List(Tool),
) -> Result(GeminiResponse, String) {
  let url = "https://generativelanguage.googleapis.com/v1beta/models/" <> model <> ":generateContent?key=" <> api_key
  
  let contents = list.map(messages, fn(m) {
    json.object([
      #("role", json.string(case m.role { "assistant" -> "model" _ -> "user" })),
      #("parts", json.array([
        json.object([#("text", json.string(m.content))])
      ], of: fn(x) { x }))
    ])
  })

  let req_body_fields = [
    #("system_instruction", json.object([
      #("parts", json.array([
        json.object([#("text", json.string(system_instruction))])
      ], of: fn(x) { x }))
    ])),
    #("contents", json.array(contents, of: fn(x) { x }))
  ]

  let req_body_fields = case tools {
    [] -> req_body_fields
    _ -> {
      let tool_json = json.object([
        #("function_declarations", json.array(
          list.map(tools, fn(t) {
            json.object([
              #("name", json.string(t.name)),
              #("description", json.string(t.description)),
              #("parameters", t.parameters)
            ])
          }),
          of: fn(x) { x }
        ))
      ])
      list.append(req_body_fields, [#("tools", json.array([tool_json], of: fn(x) { x }))])
    }
  }

  let body = json.object(req_body_fields) |> json.to_string()

  let assert Ok(req) = request.to(url)
  let req = req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)

  case hackney.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> decode_response(resp.body)
        _ -> Error("API Error " <> string.inspect(resp.status) <> ": " <> resp.body)
      }
    }
    Error(err) -> Error("HTTP Request failed: " <> string.inspect(err))
  }
}

pub fn embed(api_key: String, model: String, text: String) -> Result(List(Float), String) {
  let url = "https://generativelanguage.googleapis.com/v1beta/models/" <> model <> ":embedContent?key=" <> api_key
  
  let body = json.object([
    #("content", json.object([
      #("parts", json.array([
        json.object([#("text", json.string(text))])
      ], of: fn(x) { x }))
    ]))
  ]) |> json.to_string()

  let assert Ok(req) = request.to(url)
  let req = req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
    
  case hackney.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> decode_embedding(resp.body)
        _ -> Error("Embedding API Error " <> string.inspect(resp.status) <> ": " <> resp.body)
      }
    }
    Error(err) -> Error("HTTP Request failed: " <> string.inspect(err))
  }
}

fn decode_response(body_string: String) -> Result(GeminiResponse, String) {
  // 1. Try text response
  // candidates[0].content.parts[0].text
  let text_decoder = {
    decode.at(["candidates"], 
      decode.at([0], 
        decode.at(["content", "parts"], 
          decode.at([0], 
            decode.at(["text"], decode.string)
          )
        )
      )
    )
    |> decode.map(TextResponse)
  }
  
  case json.parse(from: body_string, using: text_decoder) {
    Ok(resp) -> Ok(resp)
    Error(_) -> {
      // 2. Try tool call response
      // candidates[0].content.parts[0].functionCall
      let tool_call_decoder = {
        use name <- decode.field("name", decode.string)
        use args <- decode.field("args", decode.dict(decode.string, decode.dynamic))
        decode.success(ToolCall(name, args))
      }

      let tool_decoder = {
        decode.at(["candidates"], 
          decode.at([0], 
            decode.at(["content", "parts"], 
              decode.at([0], 
                decode.at(["functionCall"], tool_call_decoder)
              )
            )
          )
        )
        |> decode.map(fn(call) { ToolCallResponse([call]) })
      }
      
      case json.parse(from: body_string, using: tool_decoder) {
        Ok(resp) -> Ok(resp)
        Error(err) -> Error("Failed to decode Gemini response: " <> string.inspect(err) <> "\nBody: " <> body_string)
      }
    }
  }
}

fn decode_embedding(body_string: String) -> Result(List(Float), String) {
  let embedding_decoder = {
    decode.at(["embedding", "values"], decode.list(decode.float))
  }
  
  case json.parse(from: body_string, using: embedding_decoder) {
    Ok(values) -> Ok(values)
    Error(err) -> Error("Failed to decode embedding: " <> string.inspect(err))
  }
}
