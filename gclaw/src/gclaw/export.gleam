import gleam/int
import gleam/float
import gleam/list
import gleam/string
import gleamdb/fact

pub type ExportFormat {
  Markdown
  JSON
}

pub fn to_markdown(facts: List(fact.Fact)) -> String {
  let header = "# GClaw Memory Export\n\n"
  let body = list.map(facts, format_fact) |> string.join("\n---\n")
  header <> body
}

fn format_fact(f: fact.Fact) -> String {
  let #(entity, attribute, value) = f
  let content = case value {
    fact.Str(s) -> s
    fact.Int(i) -> int.to_string(i)
    fact.Float(fl) -> float.to_string(fl)
    fact.Bool(b) -> case b { True -> "true" False -> "false" }
    _ -> "complex value"
  }
  
  let eid_str = case entity {
    fact.Uid(fact.EntityId(id)) -> int.to_string(id)
    _ -> "lookup-ref"
  }

  "## Fact " <> eid_str <> "\n" <>
  "- Attribute: " <> attribute <> "\n" <>
  "- Value: " <> content <> "\n"
}
