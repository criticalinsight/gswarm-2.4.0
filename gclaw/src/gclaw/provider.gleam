import gleam/list
import gleam/int
import gleam/result

pub type Provider {
  Gemini
  OpenAI
  Anthropic
  Local
}

pub type Capabilities {
  Capabilities(
    text_generation: Bool,
    image_analysis: Bool,
    function_calling: Bool,
    max_tokens: Int,
  )
}

pub fn auto_select(required_caps: Capabilities, available: List(#(Provider, Capabilities))) -> Result(Provider, Nil) {
  // Simple strategy: Filter by capabilities and pick the one with max tokens
  available
  |> list.filter(fn(pair) {
    let caps = pair.1
    caps.text_generation == required_caps.text_generation &&
    caps.image_analysis == required_caps.image_analysis &&
    caps.function_calling == required_caps.function_calling &&
    caps.max_tokens >= required_caps.max_tokens
  })
  |> list.sort(fn(a, b) { int.compare(b.1.max_tokens, a.1.max_tokens) }) // Descending
  |> list.first
  |> result.map(fn(pair) { pair.0 })
}
