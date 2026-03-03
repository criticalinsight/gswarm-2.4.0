import gleam/option.{type Option}

pub type MemoryType {
  Conversation
  Document
  CodeSnippet
  Observation
  Plan
}

pub const type_attr = "type"
pub const content_attr = "content"
pub const source_attr = "source"
pub const timestamp_attr = "timestamp"
pub const tags_attr = "tags"
pub const importance_attr = "importance"
pub const sentiment_attr = "sentiment"

pub fn to_string(mt: MemoryType) -> String {
  case mt {
    Conversation -> "conversation"
    Document -> "document"
    CodeSnippet -> "code_snippet"
    Observation -> "observation"
    Plan -> "plan"
  }
}

pub fn from_string(s: String) -> Option(MemoryType) {
  case s {
    "conversation" -> option.Some(Conversation)
    "document" -> option.Some(Document)
    "code_snippet" -> option.Some(CodeSnippet)
    "observation" -> option.Some(Observation)
    "plan" -> option.Some(Plan)
    _ -> option.None
  }
}
