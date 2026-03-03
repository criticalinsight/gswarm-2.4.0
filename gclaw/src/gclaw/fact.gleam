import gleam/list
import gleam/string
import gleamdb/fact

pub const msg_content = "msg/content"
pub const msg_role = "msg/role"
pub const msg_session = "msg/session"
pub const msg_timestamp = "msg/timestamp"
pub const mem_summary = "mem/summary"
pub const mem_vector = "mem/vector"
pub const tool_call = "tool/call"
pub const tool_result = "tool/result"

pub fn value_to_string(v: fact.Value) -> String {
  case v {
    fact.Str(s) -> s
    fact.Int(i) -> string.inspect(i)
    fact.Float(f) -> string.inspect(f)
    fact.Bool(b) -> string.inspect(b)
    fact.Vec(floats) -> "[" <> string.join(list.map(floats, string.inspect), ", ") <> "]"
    _ -> ""
  }
}

pub fn format_datom(d: fact.Datom) -> String {
  "[" <> d.attribute <> "]: " <> value_to_string(d.value)
}
