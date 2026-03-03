# GleamCMS Editor: Lustre & Wisp Symmetry 🧙🏾‍♂️

The GleamCMS Editor is a hybrid application that combines **Server-Side Rendering (SSR)** with **Client-Side Interactivity (CSR)**.

## 1. Process-Oriented Design (MVU)
We use the Model-View-Update pattern where the state is managed by a single process loop.

- **Model**: `Post` record (Title, Slug, Content, Status).
- **Msg**: Current events (`SetTitle`, `SetStatus`, `Save`).
- **Update**: Pure function transitions `Model + Msg -> (Model, Effect)`.

## 2. Hybrid Architecture
To maximize performance and SEO (for public views) while enabling rich editing:

- **SSR (Wisp)**: The initial page load is rendered server-side by `wisp`. The HTML includes the initial state embedded in the DOM.
- **CSR (Lustre)**: The client-side JavaScript bundle hydrates the DOM and takes over the event loop.

## 3. The Save Loop
The editor communicates with the backend via the `Save` effect.

1.  **User Click**: Dispatches `Save` msg to the update loop.
2.  **Effect**: Triggered by `update`, sends a `POST /api/publish` request via `lustre/http` (or native fetch integration).
3.  **Response**: On success, the backend returns `200 OK`, and the editor displays a success notification.
4.  **Error Handling**: If validation fails (e.g. invalid slug), the editor displays the error message without losing the user's draft.

## 5. Interactive Flourishes
The frontend includes a set of lightweight JS/CSS flourishes triggered by AI site specifications:
- **Scroll Reveal**: An `IntersectionObserver` that adds the `.revealed` class to sections as they enter the viewport.
- **Section Transistions**: CSS-driven fade-ins with upward motion for a premium "WordPress-level" feel.
- **Grid Balance**: Dynamic spacing variations (`airy`, `compact`) defined in the `ThemeConfig` and injected as CSS variables.

## 4. Styling (Premium Glassmorphism)
The editor uses a custom `editor.css` based on the Inter font family and modern CSS variables for dark mode support.

### Parametric Theming
GleamCMS supports 50+ themes generated via `configurable.gleam`.
- **CSS Variables**: Themes inject variables like `--bg-color`, `--text-color`, and `--accent-color` into the `:root` scope.
- **Consistency**: The editor and the generated site share the same design tokens, ensuring WYSIWYG fidelity.
- **Dark Mode**: A simple JS toggle switches the variables at runtime.
