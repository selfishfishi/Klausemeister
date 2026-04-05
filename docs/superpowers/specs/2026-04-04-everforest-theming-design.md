# Everforest Theming System

## Overview

A unified theming system with 6 built-in Everforest color variants that control both the terminal palette (via ghostty config) and the app chrome (via SwiftUI environment). Theme selection persists across app restarts via `@AppStorage`.

## Theme Variants

| Variant | Background Style | Mode |
|---------|-----------------|------|
| Dark Hard | Deepest backgrounds | Dark |
| Dark Medium | Default dark | Dark |
| Dark Soft | Lighter dark | Dark |
| Light Hard | Brightest backgrounds | Light |
| Light Medium | Default light | Light |
| Light Soft | Muted light | Light |

Default theme: **Dark Medium**.

## Data Model

### AppTheme enum

```swift
enum AppTheme: String, CaseIterable, Codable {
    case darkHard, darkMedium, darkSoft
    case lightHard, lightMedium, lightSoft
}
```

Stored in `@AppStorage("selectedTheme")`. Raw string value used for persistence.

### ThemeColors struct

```swift
struct ThemeColors {
    // App chrome
    let accentColor: Color        // primary accent (green)
    let sidebarTint: Color        // sidebar glass tint

    // Terminal palette (passed to ghostty config)
    let background: String        // hex
    let foreground: String        // hex
    let palette: [String]         // 16 ANSI colors
    let cursorColor: String       // hex
    let selectionBg: String       // hex
    let selectionFg: String       // hex
}
```

Each `AppTheme` case maps to a `ThemeColors` via a computed property `var colors: ThemeColors`.

## Everforest Palette

### Dark Variants

Foreground and accent colors are shared across all dark variants:

- **fg:** `#D3C6AA`
- **red:** `#E67E80`, **orange:** `#E69875`, **yellow:** `#DBBC7F`
- **green:** `#A7C080`, **aqua:** `#83C092`, **blue:** `#7FBBB3`, **purple:** `#D699B6`
- **grey0:** `#7A8478`, **grey1:** `#859289`, **grey2:** `#9DA9A0`

Background colors vary by contrast level:

| Key | Hard | Medium | Soft |
|-----|------|--------|------|
| bg_dim | `#1E2326` | `#232A2E` | `#293136` |
| bg0 | `#272E33` | `#2D353B` | `#333C43` |
| bg1 | `#2E383C` | `#343F44` | `#3A464C` |
| bg2 | `#374145` | `#3D484D` | `#434F55` |
| bg3 | `#414B50` | `#475258` | `#4D5960` |
| bg4 | `#495156` | `#4F585E` | `#555F66` |
| bg5 | `#4F5B58` | `#56635f` | `#5D6B66` |
| bg_visual | `#4C3743` | `#543A48` | `#5C3F4F` |

### Light Variants

Foreground and accent colors are shared across all light variants:

- **fg:** `#5C6A72`
- **red:** `#F85552`, **orange:** `#F57D26`, **yellow:** `#DFA000`
- **green:** `#8DA101`, **aqua:** `#35A77C`, **blue:** `#3A94C5`, **purple:** `#DF69BA`
- **grey0:** `#A6B0A0`, **grey1:** `#939F91`, **grey2:** `#829181`

| Key | Hard | Medium | Soft |
|-----|------|--------|------|
| bg_dim | `#F2EFDF` | `#EFEBD4` | `#E5DFC5` |
| bg0 | `#FFFBEF` | `#FDF6E3` | `#F3EAD3` |
| bg1 | `#F8F5E4` | `#F4F0D9` | `#EAE4CA` |
| bg2 | `#F2EFDF` | `#EFEBD4` | `#E5DFC5` |
| bg3 | `#EDEADA` | `#E6E2CC` | `#DDD8BE` |
| bg4 | `#E8E5D5` | `#E0DCC7` | `#D8D3BA` |
| bg5 | `#BEC5B2` | `#BDC3AF` | `#B9C0AB` |
| bg_visual | `#F0F2D4` | `#EAEDC8` | `#E1E4BD` |

## ANSI Color Mapping

### Dark variants

| ANSI | Role | Color |
|------|------|-------|
| 0 (black) | bg1 | per-variant |
| 1 (red) | red | `#E67E80` |
| 2 (green) | green | `#A7C080` |
| 3 (yellow) | yellow | `#DBBC7F` |
| 4 (blue) | blue | `#7FBBB3` |
| 5 (magenta) | purple | `#D699B6` |
| 6 (cyan) | aqua | `#83C092` |
| 7 (white) | fg | `#D3C6AA` |
| 8 (bright black) | grey0 | `#7A8478` |
| 9 (bright red) | red | `#E67E80` |
| 10 (bright green) | green | `#A7C080` |
| 11 (bright yellow) | orange | `#E69875` |
| 12 (bright blue) | blue | `#7FBBB3` |
| 13 (bright magenta) | purple | `#D699B6` |
| 14 (bright cyan) | aqua | `#83C092` |
| 15 (bright white) | grey2 | `#9DA9A0` |

### Light variants

| ANSI | Role | Color |
|------|------|-------|
| 0 (black) | bg1 | per-variant |
| 1 (red) | red | `#F85552` |
| 2 (green) | green | `#8DA101` |
| 3 (yellow) | yellow | `#DFA000` |
| 4 (blue) | blue | `#3A94C5` |
| 5 (magenta) | purple | `#DF69BA` |
| 6 (cyan) | aqua | `#35A77C` |
| 7 (white) | fg | `#5C6A72` |
| 8 (bright black) | grey0 | `#A6B0A0` |
| 9 (bright red) | red | `#F85552` |
| 10 (bright green) | green | `#8DA101` |
| 11 (bright yellow) | orange | `#F57D26` |
| 12 (bright blue) | blue | `#3A94C5` |
| 13 (bright magenta) | purple | `#DF69BA` |
| 14 (bright cyan) | aqua | `#35A77C` |
| 15 (bright white) | grey2 | `#829181` |

### Special colors

- **Background:** `bg0` from selected variant
- **Foreground:** `fg` from selected variant
- **Cursor:** green accent (`#A7C080` dark, `#8DA101` light)
- **Selection background:** `bg_visual` from selected variant
- **Selection foreground:** `fg` from selected variant

## Architecture

### State management

Theme is a simple user preference, not complex application state. No `ThemeFeature` reducer needed.

- `@AppStorage("selectedTheme")` holds the raw string value
- Default: `darkMedium`
- Read directly in views and at ghostty init time

### SwiftUI environment propagation

A custom `EnvironmentKey` injects `ThemeColors` into the view hierarchy:

```swift
struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = AppTheme.darkMedium.colors
}
```

Set at the root `WindowGroup` level. All child views read `@Environment(\.themeColors)`.

### App chrome application

- Sidebar glass tint: `.glassEffect(.regular.tint(theme.accentColor))`
- Toolbar tint: `.tint(theme.accentColor)`
- Accent color propagation: `.accentColor(theme.accentColor)`

### Terminal color application

Colors are applied to ghostty via `ghostty_config_set(config, key, value)` before `ghostty_config_finalize()`:

- `ghostty_config_set(cfg, "background", bg0Hex)`
- `ghostty_config_set(cfg, "foreground", fgHex)`
- `ghostty_config_set(cfg, "palette", "0=#XXXXXX")` for each of 16 slots
- `ghostty_config_set(cfg, "cursor-color", cursorHex)`
- `ghostty_config_set(cfg, "selection-background", selBgHex)`
- `ghostty_config_set(cfg, "selection-foreground", selFgHex)`

### Theme change at runtime

1. User selects theme from menu bar
2. `@AppStorage("selectedTheme")` updates
3. App chrome updates immediately via SwiftUI environment propagation
4. Ghostty config is rebuilt with new palette colors
5. Ghostty app is recreated (`ghostty_app_new`)
6. Active tab IDs are preserved in TCA state; surfaces are destroyed and recreated with new colors

`GhosttyAppClient` gains a `rebuildWithTheme` method:

```swift
var rebuildWithTheme: @Sendable @MainActor (AppTheme) -> Void
```

This calls into `GhosttyApp.shared` to tear down and reinitialize with the new config.

### Theme picker UI

A `CommandMenu("Theme")` in `KlausemeisterApp.swift`:

```
Theme
  Dark
    Hard
    Medium   (checkmark if selected)
    Soft
  Light
    Hard
    Medium
    Soft
```

Each item toggles `@AppStorage("selectedTheme")` and triggers the ghostty rebuild.

## File Structure

```
Klausemeister/Theme/
    AppTheme.swift           — enum, ThemeColors struct, EnvironmentKey
    EverforestPalette.swift  — static color definitions for all 6 variants
```

Changes to existing files:
- `GhosttyApp.swift` — accept ThemeColors, apply config, support rebuild
- `GhosttyAppClient.swift` — add `rebuildWithTheme` method
- `KlausemeisterApp.swift` — add Theme menu, inject theme environment, trigger rebuild on change
- `TerminalContainerView.swift` — read theme from environment, apply tints
- `SidebarView.swift` — apply sidebar glass tint from theme

## Not in Scope

- Custom/user-defined themes
- Per-tab themes
- Theme preview/live preview
- Import/export
- Automatic light/dark switching based on system appearance
