import gleam/list
import gleamdb/gleamcms/theme.{type Theme}
import gleamdb/gleamcms/themes/configurable.{type ThemeConfig, ThemeConfig}

pub fn get_all() -> List(Theme) {
  get_configs()
  |> list.map(configurable.new)
}

pub fn get_configs() -> List(ThemeConfig) {
  [
    ThemeConfig("Default Dark", "#0f172a", "#f8fafc", "#3b82f6", "#1e293b", "#1e293b99", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Paper White", "#ffffff", "#0f172a", "#2563eb", "#e2e8f0", "#f1f5f9", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Midnight Purple", "#2e1065", "#faf5ff", "#d8b4fe", "#4c1d95", "#581c87", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Forest Green", "#052e16", "#f0fdf4", "#4ade80", "#14532d", "#14532d", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Ocean Blue", "#0c4a6e", "#f0f9ff", "#38bdf8", "#075985", "#0369a1", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Coffee", "#451a03", "#fffbeb", "#fbbf24", "#78350f", "#78350f", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Cyberpunk", "#000000", "#00ff00", "#ff00ff", "#333333", "#111111", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Monokai", "#272822", "#f8f8f2", "#a6e22e", "#3e3d32", "#3e3d32", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Dracula", "#282a36", "#f8f8f2", "#bd93f9", "#44475a", "#44475a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Nord", "#2e3440", "#d8dee9", "#88c0d0", "#3b4252", "#3b4252", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Solarized Dark", "#002b36", "#839496", "#b58900", "#073642", "#073642", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Solarized Light", "#fdf6e3", "#657b83", "#268bd2", "#eee8d5", "#eee8d5", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Gruvbox Dark", "#282828", "#ebdbb2", "#fabd2f", "#3c3836", "#3c3836", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Gruvbox Light", "#fbf1c7", "#3c3836", "#d79921", "#ebdbb2", "#ebdbb2", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("One Dark", "#282c34", "#abb2bf", "#61afef", "#3e4451", "#3e4451", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Tokyo Night", "#1a1b26", "#c0caf5", "#7aa2f7", "#292e42", "#292e42", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Catppuccin Macchiato", "#24273a", "#cad3f5", "#c6a0f6", "#363a4f", "#363a4f", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Catppuccin Latte", "#eff1f5", "#4c4f69", "#8839ef", "#ccd0da", "#ccd0da", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Rose Pine", "#191724", "#e0def4", "#ebbcba", "#26233a", "#26233a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Synthwave", "#2b213a", "#fffbf3", "#ff79c6", "#45316d", "#45316d", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("High Contrast", "#000000", "#ffffff", "#ffff00", "#ffffff", "#000000", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Sepia", "#f4ecd8", "#5b4636", "#8f5902", "#e4d5b7", "#e4d5b7", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Slate", "#020617", "#e2e8f0", "#94a3b8", "#1e293b", "#0f172a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Zinc", "#18181b", "#fafafa", "#a1a1aa", "#27272a", "#27272a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Stone", "#1c1917", "#fafaf9", "#a8a29e", "#292524", "#292524", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Red", "#450a0a", "#fef2f2", "#f87171", "#7f1d1d", "#7f1d1d", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Orange", "#431407", "#fff7ed", "#fb923c", "#7c2d12", "#7c2d12", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Amber", "#451a03", "#fffbeb", "#fbbf24", "#78350f", "#78350f", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Yellow", "#422006", "#fefce8", "#facc15", "#713f12", "#713f12", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Lime", "#1a2e05", "#f7fee7", "#a3e635", "#365314", "#365314", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Green", "#052e16", "#f0fdf4", "#4ade80", "#14532d", "#14532d", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Emerald", "#022c22", "#ecfdf5", "#34d399", "#064e3b", "#064e3b", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Teal", "#042f2e", "#f0fdfa", "#2dd4bf", "#115e59", "#115e59", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Cyan", "#083344", "#ecfeff", "#22d3ee", "#164e63", "#164e63", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Sky", "#0c4a6e", "#f0f9ff", "#38bdf8", "#075985", "#075985", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Blue", "#172554", "#eff6ff", "#60a5fa", "#1e3a8a", "#1e3a8a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Indigo", "#1e1b4b", "#eef2ff", "#818cf8", "#312e81", "#312e81", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Violet", "#2e1065", "#f5f3ff", "#a78bfa", "#4c1d95", "#4c1d95", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Purple", "#3b0764", "#faf5ff", "#c084fc", "#581c87", "#581c87", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Fuchsia", "#4a044e", "#fdf4ff", "#e879f9", "#701a75", "#701a75", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Pink", "#500724", "#fdf2f8", "#f472b6", "#831843", "#831843", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Rose", "#4c0519", "#fff1f2", "#fb7185", "#881337", "#881337", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Steel", "#273444", "#ffffff", "#8492a6", "#3c4858", "#3c4858", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Vaporwave", "#1c0b19", "#00f0ff", "#ff0080", "#2d162a", "#2d162a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Matrix", "#000000", "#00ff00", "#003300", "#001100", "#001100", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Hacker", "#0d0d0d", "#33ff00", "#39ff14", "#1a1a1a", "#1a1a1a", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Ubuntu", "#300a24", "#ffffff", "#e95420", "#aea79f", "#aea79f", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Facebook", "#1877f2", "#ffffff", "#4267b2", "#898f9c", "#898f9c", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Twitter", "#1da1f2", "#ffffff", "#14171a", "#657786", "#657786", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Discord", "#36393f", "#dcddde", "#7289da", "#2f3136", "#2f3136", "Inter", "standard", "subtle", "soft", "standard", ""),
    ThemeConfig("Rotary Club Classic", "#FFFFFF", "#2D2D2D", "#015491", "#D1A10E", "#F9F9F9", "Montserrat", "hero-split", "elevated", "soft", "airy", ".logo { font-size: 2rem; border-left: 4px solid var(--accent-color); padding-left: 1rem; }"),
  ]
}
