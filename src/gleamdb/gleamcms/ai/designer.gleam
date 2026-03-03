pub type SectionDescriptor {
  SectionDescriptor(
    title: String,
    content: String,
    section_type: String,
  )
}

pub type ThemeConfig {
  ThemeConfig(
    name: String,
    bg_color: String,
    text_color: String,
    accent_color: String,
    border_color: String,
    card_bg: String,
    font_family: String,
    layout_style: String,
    shadow_depth: String,
    border_radius: String,
    spacing_scale: String,
    custom_flourish: String,
    sections: List(SectionDescriptor),
  )
}

import gleam/json
import gleam/list
import gleam/dynamic/decode
import gleam/string

@external(erlang, "gleamcms_httpc_ffi", "shell_exec")
pub fn shell_exec(command: String) -> Result(String, String)

@external(erlang, "gleamcms_httpc_ffi", "get_env")
pub fn get_env(name: String) -> Result(String, Nil)

pub fn design_theme(
  prompt: String,
  _project_id: String,
  _bearer_token: String,
) -> Result(ThemeConfig, String) {
  let system_instruction = "You are a World-Class Digital Agency Lead. Generate a premium landing page specification for GleamCMS in JSON format. The JSON must have these exact keys: name, bg_color, text_color, accent_color, border_color, card_bg, font_family, layout_style, shadow_depth, border_radius, spacing_scale, custom_flourish, sections. Each section in the 'sections' list MUST have three keys: 'title', 'content', and 'section_type'. Valid 'section_type' values are: 'hero', 'features', 'stats', 'cta', 'content'. Output ONLY the JSON object."

  let escaped_prompt = string.replace(prompt, "'", "'\\''")
  let escaped_system = string.replace(system_instruction, "'", "'\\''")
  
  let cmd = "gemini -p '" <> escaped_system <> " Prompt: " <> escaped_prompt <> "'"

  case shell_exec(cmd) {
    Ok(resp) -> parse_gemini_response(resp)
    Error(e) -> Error(e)
  }
}

fn parse_gemini_response(output: String) -> Result(ThemeConfig, String) {
  // The CLI might output multiple JSON objects. We split by potential top-level starts.
  let parts = string.split(output, "\n{")
  let configs = list.filter_map(parts, fn(part) {
    let candidate = case string.starts_with(part, "{") {
      True -> part
      False -> "{" <> part
    }
    case json.parse(from: extract_json(candidate), using: theme_config_decoder()) {
      Ok(config) -> Ok(config)
      Error(_) -> Error(Nil)
    }
  })

  case list.last(configs) {
    Ok(config) -> Ok(config)
    Error(_) -> Error("Failed to find valid GleamCMS theme config in output.")
  }
}

fn extract_json(input: String) -> String {
  let reversed = string.reverse(input)
  case string.split_once(reversed, "}") {
    Ok(#(_, rest)) -> string.reverse("}" <> rest)
    Error(_) -> input
  }
}

fn theme_config_decoder() {
  use name <- decode.field("name", decode.string)
  use bg_color <- decode.field("bg_color", decode.string)
  use text_color <- decode.field("text_color", decode.string)
  use accent_color <- decode.field("accent_color", decode.string)
  use border_color <- decode.field("border_color", decode.string)
  use card_bg <- decode.field("card_bg", decode.string)
  use font_family <- decode.field("font_family", decode.string)
  use layout_style <- decode.field("layout_style", decode.string)
  use shadow_depth <- decode.field("shadow_depth", decode.string)
  use border_radius <- decode.field("border_radius", decode.string)
  use spacing_scale <- decode.field("spacing_scale", decode.string)
  use custom_flourish <- decode.field("custom_flourish", decode.string)
  use sections <- decode.field("sections", decode.list(section_decoder()))
  decode.success(ThemeConfig(
    name, bg_color, text_color, accent_color, border_color, card_bg, font_family,
    layout_style, shadow_depth, border_radius, spacing_scale, custom_flourish, sections
  ))
}

fn section_decoder() {
  use title <- decode.optional_field("title", "Untitled Section", decode.string)
  use content <- decode.optional_field("content", "", decode.string)
  use section_type <- decode.optional_field("section_type", "content", decode.string)
  decode.success(SectionDescriptor(title, content, section_type))
}
