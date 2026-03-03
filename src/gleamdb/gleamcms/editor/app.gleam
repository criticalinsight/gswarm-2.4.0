import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/attribute
import lustre/event
import gleam/json
import gleam/list
import gleam/string
import gleamdb/gleamcms/db/post.{type PostStatus, Draft}
import gleamdb/gleamcms/builder/theme as theme_provider

// ---------------------------------------------------------------------------
// Server-side render entry point
// ---------------------------------------------------------------------------

pub fn render() -> String {
  let names = theme_provider.theme_names()
  element.to_string(
    html.div([attribute.id("app")], [
      html.link([attribute.rel("stylesheet"), attribute.href("/static/editor.css")]),
      view(Model("", "", "", Draft, "Default Dark", False, "")),
      theme_script(names),
      html.script([attribute.type_("module"), attribute.src("/static/editor.js")], ""),
    ])
  )
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

pub type Model {
  Model(
    title: String,
    slug: String,
    content: String,
    status: PostStatus,
    selected_theme: String,
    generated: Bool,
    generated_slug: String,
  )
}

pub type Msg {
  SetTitle(String)
  SetSlug(String)
  SetContent(String)
  SetStatus(PostStatus)
  SetTheme(String)
  Save
  Generate
  GenerateDone(String)
}

// ---------------------------------------------------------------------------
// Init / Update
// ---------------------------------------------------------------------------

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  #(Model("", "", "", Draft, "Default Dark", False, ""), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SetTitle(t) -> #(Model(..model, title: t), effect.none())
    SetSlug(s) -> #(Model(..model, slug: s), effect.none())
    SetContent(c) -> #(Model(..model, content: c), effect.none())
    SetStatus(s) -> #(Model(..model, status: s), effect.none())
    SetTheme(name) -> #(Model(..model, selected_theme: name), effect.none())
    Save -> #(model, save_effect(model))
    Generate -> #(model, generate_effect(model))
    GenerateDone(slug) -> #(Model(..model, generated: True, generated_slug: slug), effect.none())
  }
}

fn save_effect(model: Model) -> Effect(Msg) {
  use dispatch <- effect.from
  let _body = json.object([
    #("title", json.string(model.title)),
    #("slug", json.string(model.slug)),
    #("content", json.string(model.content)),
    #("status", json.string(post.status_to_string(model.status))),
  ]) |> json.to_string
  dispatch(Save)
  Nil
}

fn generate_effect(model: Model) -> Effect(Msg) {
  use dispatch <- effect.from
  dispatch(GenerateDone(model.slug))
  Nil
}

// ---------------------------------------------------------------------------
// Main (browser entrypoint)
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view_empty)
  let _ = lustre.start(app, "#app", Nil)
  Nil
}

fn view_empty(model: Model) -> Element(Msg) {
  view(model)
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("editor-container")], [
    html.h1([], [element.text("GleamCMS Editor")]),

    // Title
    html.div([attribute.class("form-group")], [
      html.label([], [element.text("Title")]),
      html.input([
        attribute.value(model.title),
        event.on_input(SetTitle),
        attribute.class("title-input"),
        attribute.id("field-title"),
      ]),
    ]),

    // Slug
    html.div([attribute.class("form-group")], [
      html.label([], [element.text("Slug")]),
      html.input([
        attribute.value(model.slug),
        event.on_input(SetSlug),
        attribute.class("slug-input"),
        attribute.id("field-slug"),
      ]),
    ]),

    // Content
    html.div([attribute.class("form-group")], [
      html.label([], [element.text("Content")]),
      html.textarea([
        attribute.value(model.content),
        event.on_input(SetContent),
        attribute.class("content-area"),
        attribute.id("field-content"),
      ], ""),
    ]),

    // Status
    html.div([attribute.class("form-group")], [
      html.label([], [element.text("Status")]),
      html.select([
        event.on_input(fn(v) { SetStatus(post.string_to_status(v)) }),
        attribute.class("status-select"),
        attribute.id("field-status"),
      ], [
        html.option([attribute.value("draft")], "Draft"),
        html.option([attribute.value("published")], "Published"),
        html.option([attribute.value("archived")], "Archived"),
      ]),
    ]),

    // AI Designer
    html.div([attribute.class("form-group ai-section")], [
      html.label([], [element.text("AI Theme Designer ✨")]),
      html.div([attribute.class("ai-row")], [
        html.input([
          attribute.placeholder("e.g. Neon Horizon, Arctic Snow..."),
          attribute.class("ai-input"),
          attribute.id("ai-prompt"),
        ]),
        html.button([
          attribute.class("ai-btn"),
          attribute.id("ai-btn"),
        ], [element.text("Design")]),
      ]),
    ]),

    // Theme Picker
    html.div([attribute.class("form-group")], [
      html.label([], [element.text("Theme")]),
      html.select([
        attribute.class("theme-select"),
        attribute.id("theme-picker"),
      ], [html.option([attribute.value(model.selected_theme)], model.selected_theme)]),
    ]),

    // Action row
    html.div([attribute.class("action-row")], [
      html.button([
        event.on_click(Save),
        attribute.class("save-btn"),
        attribute.id("btn-save"),
      ], [element.text("Transact Fact")]),
      html.button([
        event.on_click(Generate),
        attribute.class("generate-btn"),
        attribute.id("btn-generate"),
      ], [element.text("⚡ Generate Site")]),
    ]),

    // Generated link banner (hidden until generated)
    html.div([
      attribute.class("generated-link"),
      attribute.id("generated-link"),
      attribute.style("display", case model.generated { True -> "block" False -> "none" }),
    ], [
      element.text("✅ Sites generated! "),
      html.a([
        attribute.href("/sites"),
        attribute.id("view-sites-link"),
      ], [element.text("🌐 View All Sites")]),
    ]),
  ])
}

// ---------------------------------------------------------------------------
// JS for theme picker population + generate button
// ---------------------------------------------------------------------------

fn theme_script(names: List(String)) -> Element(Msg) {
  let names_js = "[" <> string.join(list.map(names, fn(n) { "\"" <> n <> "\"" }), ",") <> "]"
  let script = "
(function() {
  const names = " <> names_js <> ";
  const picker = document.getElementById('theme-picker');
  if (picker) {
    picker.innerHTML = '';
    names.forEach(n => {
      const o = document.createElement('option');
      o.value = n; o.textContent = n;
      picker.appendChild(o);
    });
    picker.addEventListener('change', () => {
      document.documentElement.setAttribute('data-theme', picker.value);
    });
  }

  const btn = document.getElementById('btn-generate');
  const link = document.getElementById('generated-link');
  const postLink = document.getElementById('generated-post-link');
  const slugField = document.getElementById('field-slug');
  if (btn) {
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      btn.textContent = '⏳ Generating…';
      try {
        const theme = picker ? picker.value : 'Default Dark';
      const url = '/api/generate?theme=' + encodeURIComponent(theme);
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Authorization': 'Bearer sovereign-token-2026' }
      });
        const data = await res.json();
        if (link) link.style.display = 'block';
        btn.textContent = '✅ ' + data.sites + ' site(s), ' + data.pages + ' pages';
      } catch(e) {
        btn.textContent = '❌ Generation failed';
      }
    });
  }

  const aiBtn = document.getElementById('ai-btn');
  const aiPrompt = document.getElementById('ai-prompt');
  if (aiBtn && aiPrompt) {
    aiBtn.addEventListener('click', async () => {
      const prompt = aiPrompt.value;
      if (!prompt) return;
      aiBtn.disabled = true;
      aiBtn.textContent = '⏳';
      try {
        const res = await fetch('/api/ai/design', {
          method: 'POST',
          headers: { 
            'Authorization': 'Bearer sovereign-token-2026',
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ prompt })
        });
        const config = await res.json();
        if (config.error) throw new Error(config.error);
        
        const root = document.documentElement;
        root.style.setProperty('--bg-color', config.bg_color);
        root.style.setProperty('--text-color', config.text_color);
        root.style.setProperty('--accent-color', config.accent_color);
        root.style.setProperty('--border-color', config.border_color);
        root.style.setProperty('--card-bg', config.card_bg);
        
        // Structural rhythmic properties
        const shadow = config.shadow_depth === 'elevated' ? '0 10px 25px -5px rgba(0,0,0,0.3)' : config.shadow_depth === 'subtle' ? '0 4px 6px -1px rgba(0,0,0,0.1)' : 'none';
        const radius = config.border_radius === 'round' ? '2rem' : config.border_radius === 'soft' ? '0.75rem' : config.border_radius === 'sharp' ? '0' : '0.5rem';
        const spacing = config.spacing_scale === 'airy' ? '4rem' : config.spacing_scale === 'compact' ? '1rem' : '2rem';
        
        root.style.setProperty('--shadow', shadow);
        root.style.setProperty('--radius', radius);
        root.style.setProperty('--spacing', spacing);
        
        // Layout posture
        document.body.className = 'layout-' + config.layout_style;
        
        // Custom flourish (CSS Injection)
        let styleTag = document.getElementById('ai-flourish');
        if (!styleTag) {
          styleTag = document.createElement('style');
          styleTag.id = 'ai-flourish';
          document.head.appendChild(styleTag);
        }
        styleTag.textContent = config.custom_flourish;
        
        const exists = Array.from(picker.options).some(o => o.value === config.name);
        if (!exists) {
          const o = document.createElement('option');
          o.value = config.name; o.textContent = '✨ ' + config.name;
          picker.appendChild(o);
          picker.value = config.name;
        } else {
          picker.value = config.name;
        }
        aiBtn.textContent = 'Design'; aiBtn.disabled = false;
      } catch(e) {
        aiBtn.textContent = '❌';
        setTimeout(() => { aiBtn.textContent = 'Design'; aiBtn.disabled = false; }, 2000);
      }
    });
  }
})();
"
  html.script([], script)
}
