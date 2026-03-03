import gleam/io
import gleam/list
import gleam/string
import gleam/result
import gleam/json
import gclaw/memory
import gclaw/provider/gemini
import gclaw/fact as gfact
import gleamdb/fact

@external(erlang, "gclaw_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "gclaw_ffi", "get_line")
fn get_line(prompt: String) -> Result(String, Nil)

pub fn main() {
  let api_key = case get_env("GEMINI_API_KEY") {
    Ok(k) -> k
    Error(_) -> {
      io.println("Warning: GEMINI_API_KEY not set")
      ""
    }
  }
  
  // Use persistent memory
  let mem = memory.init_persistent("gclaw.db")
  io.println("🧙🏾‍♂️: GClaw initialized. How can I help you today?")
  chat_loop(mem, api_key)
}

fn chat_loop(mem: memory.Memory, api_key: String) {
  let input = get_line("> ")
    |> result.unwrap("")
    |> string.trim()

  case input {
    "exit" | "quit" -> io.println("Bye!")
    _ -> {
      let ts = 1707880000 // Placeholder for real timestamp
      
      // 0. Generate Embedding
      let embedding = case gemini.embed(api_key, "text-embedding-004", input) {
        Ok(vec) -> vec
        Error(e) -> {
          io.println("Warning: Embedding failed: " <> e)
          []
        }
      }

      // 1. Store user message with vector
      let msg_eid = fact.deterministic_uid("msg_" <> string.inspect(ts) <> "_" <> input)
      let msg_facts = [
        #(msg_eid, gfact.msg_content, fact.Str(input)),
        #(msg_eid, gfact.msg_role, fact.Str("user")),
        #(msg_eid, gfact.msg_session, fact.Str("user")), // Fixed session for now
        #(msg_eid, gfact.msg_timestamp, fact.Int(ts))
      ]
      let mem = memory.remember_semantic(mem, msg_facts, embedding)
      
      process_gemini(mem, api_key, ts + 1, embedding)
      chat_loop(mem, api_key)
    }
  }
}

fn process_gemini(mem: memory.Memory, api_key: String, ts: Int, embedding: List(Float)) {
  let context = memory.get_context_window(mem, "user", 20, embedding)
  let sys_prompt = "You are OpenClaw (GClaw), a minimalist, fact-based AI assistant. Use tools when necessary."
  
  let gemini_msgs = list.map(context, fn(c) {
    case string.split_once(c, ": ") {
      Ok(#(role, content)) -> gemini.Message(role, content)
      Error(_) -> gemini.Message("user", c)
    }
  })

  // Define tools
  let tools = [
    gemini.Tool(
      name: "get_datetime",
      description: "Get the current date and time.",
      parameters: json.object([
        #("type", json.string("OBJECT")),
        #("properties", json.object([])),
        #("required", json.array([], of: fn(x) { x }))
      ])
    )
  ]

  case gemini.generate(api_key, "gemini-1.5-flash", sys_prompt, gemini_msgs, tools) {
    Ok(gemini.TextResponse(resp)) -> {
      io.println("Claw: " <> resp)
      let assist_eid = fact.deterministic_uid("assist_" <> string.inspect(ts))
      let assist_facts = [
        #(assist_eid, gfact.msg_content, fact.Str(resp)),
        #(assist_eid, gfact.msg_role, fact.Str("assistant")),
        #(assist_eid, gfact.msg_session, fact.Str("user")),
        #(assist_eid, gfact.msg_timestamp, fact.Int(ts))
      ]
      let _ = memory.remember(mem, assist_facts)
      Nil
    }
    Ok(gemini.ToolCallResponse(calls)) -> {
      list.each(calls, fn(call) {
        io.println("Executing tool: " <> call.name)
        case call.name {
          "get_datetime" -> {
            let result_str = "2026-02-14 05:15:00" // Mocked
            io.println("Tool Result: " <> result_str)
            
            // Store tool call and result as facts
            let tool_eid = fact.deterministic_uid("tool_" <> string.inspect(ts))
            let tool_facts = [
              #(tool_eid, gfact.msg_content, fact.Str("Executed " <> call.name <> " -> " <> result_str)),
              #(tool_eid, gfact.msg_role, fact.Str("assistant")), // Treat as part of assistant's internal thought
              #(tool_eid, gfact.msg_session, fact.Str("user")),
              #(tool_eid, gfact.msg_timestamp, fact.Int(ts))
            ]
            let mem = memory.remember(mem, tool_facts)
            
            // Re-query Gemini with the tool result (recursive call for simplicity)
            // For tool results, we might want to re-embed the result or just use the original query vector context
            process_gemini(mem, api_key, ts + 1, embedding)
          }
          _ -> {
            io.println("Unknown tool: " <> call.name)
          }
        }
      })
    }
    Error(err) -> {
      io.println("Error: " <> err)
    }
  }
}
