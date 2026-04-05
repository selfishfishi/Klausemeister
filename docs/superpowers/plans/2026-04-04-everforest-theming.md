# Everforest Theming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 built-in Everforest color themes that control both terminal palette and app chrome, switchable from the menu bar.

**Architecture:** Theme data model (`AppTheme` enum + `ThemeColors` struct) defines colors. Terminal colors are applied by writing a ghostty config file and loading it via `ghostty_config_load_file`. App chrome colors propagate via SwiftUI `EnvironmentKey`. Theme changes trigger a full ghostty app rebuild with surface recreation.

**Tech Stack:** Swift, SwiftUI, TCA (ComposableArchitecture), GhosttyKit C API

**Spec:** `docs/superpowers/specs/2026-04-04-everforest-theming-design.md`

---

## File Structure

**New files:**
- `Klausemeister/Theme/AppTheme.swift` — enum, ThemeColors struct, computed color mappings, EnvironmentKey
- `Klausemeister/Theme/EverforestPalette.swift` — static palette data for all 6 variants

**Modified files:**
- `Klausemeister/Terminal/GhosttyApp.swift` — accept theme, write config file, support rebuild
- `Klausemeister/Dependencies/GhosttyAppClient.swift` — add `rebuild` method
- `Klausemeister/Dependencies/SurfaceStore.swift` — add `destroyAll` and `recreateAll`
- `Klausemeister/Dependencies/SurfaceManager.swift` — add `recreateAllSurfaces`
- `Klausemeister/AppFeature.swift` — add `themeChanged` action
- `Klausemeister/KlausemeisterApp.swift` — add Theme menu, `@AppStorage`, inject environment, trigger rebuild
- `Klausemeister/TerminalContainerView.swift` — apply theme accent tint
- `Klausemeister/Views/SidebarView.swift` — apply sidebar glass tint from theme

---

### Task 1: Create AppTheme enum and ThemeColors struct

**Files:**
- Create: `Klausemeister/Theme/AppTheme.swift`

- [ ] **Step 1: Create the Theme directory**

```bash
mkdir -p Klausemeister/Theme
```

- [ ] **Step 2: Write AppTheme.swift**

```swift
import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case darkHard, darkMedium, darkSoft
    case lightHard, lightMedium, lightSoft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .darkHard: "Dark Hard"
        case .darkMedium: "Dark Medium"
        case .darkSoft: "Dark Soft"
        case .lightHard: "Light Hard"
        case .lightMedium: "Light Medium"
        case .lightSoft: "Light Soft"
        }
    }

    var isDark: Bool {
        switch self {
        case .darkHard, .darkMedium, .darkSoft: true
        case .lightHard, .lightMedium, .lightSoft: false
        }
    }
}

struct ThemeColors {
    let accentColor: Color
    let background: String
    let foreground: String
    let palette: [String]
    let cursorColor: String
    let selectionBg: String
    let selectionFg: String
}

struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = AppTheme.darkMedium.colors
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
```

Note: `AppTheme.darkMedium.colors` is defined in Task 2. This file will not compile until Task 2 is complete.

- [ ] **Step 3: Add file to Xcode project**

Add `Klausemeister/Theme/AppTheme.swift` to the Klausemeister target in `Klausemeister.xcodeproj`. Create a "Theme" group under the Klausemeister group.

---

### Task 2: Create Everforest palette definitions

**Files:**
- Create: `Klausemeister/Theme/EverforestPalette.swift`

- [ ] **Step 1: Write EverforestPalette.swift with all 6 variants**

This file defines the `colors` computed property on `AppTheme`. Background colors vary per variant; foreground/accent colors are shared within dark and light families.

```swift
import SwiftUI

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .darkHard:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#272E33",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#2E383C"),
                cursorColor: "#A7C080",
                selectionBg: "#4C3743",
                selectionFg: "#D3C6AA"
            )
        case .darkMedium:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#2D353B",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#343F44"),
                cursorColor: "#A7C080",
                selectionBg: "#543A48",
                selectionFg: "#D3C6AA"
            )
        case .darkSoft:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#333C43",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#3A464C"),
                cursorColor: "#A7C080",
                selectionBg: "#5C3F4F",
                selectionFg: "#D3C6AA"
            )
        case .lightHard:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#FFFBEF",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#F8F5E4"),
                cursorColor: "#8DA101",
                selectionBg: "#F0F2D4",
                selectionFg: "#5C6A72"
            )
        case .lightMedium:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#FDF6E3",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#F4F0D9"),
                cursorColor: "#8DA101",
                selectionBg: "#EAEDC8",
                selectionFg: "#5C6A72"
            )
        case .lightSoft:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#F3EAD3",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#EAE4CA"),
                cursorColor: "#8DA101",
                selectionBg: "#E1E4BD",
                selectionFg: "#5C6A72"
            )
        }
    }
}

private func darkPalette(bg1: String) -> [String] {
    [
        bg1,       // 0  black
        "#E67E80", // 1  red
        "#A7C080", // 2  green
        "#DBBC7F", // 3  yellow
        "#7FBBB3", // 4  blue
        "#D699B6", // 5  magenta
        "#83C092", // 6  cyan
        "#D3C6AA", // 7  white
        "#7A8478", // 8  bright black
        "#E67E80", // 9  bright red
        "#A7C080", // 10 bright green
        "#E69875", // 11 bright yellow (orange)
        "#7FBBB3", // 12 bright blue
        "#D699B6", // 13 bright magenta
        "#83C092", // 14 bright cyan
        "#9DA9A0", // 15 bright white
    ]
}

private func lightPalette(bg1: String) -> [String] {
    [
        bg1,       // 0  black
        "#F85552", // 1  red
        "#8DA101", // 2  green
        "#DFA000", // 3  yellow
        "#3A94C5", // 4  blue
        "#DF69BA", // 5  magenta
        "#35A77C", // 6  cyan
        "#5C6A72", // 7  white
        "#A6B0A0", // 8  bright black
        "#F85552", // 9  bright red
        "#8DA101", // 10 bright green
        "#F57D26", // 11 bright yellow (orange)
        "#3A94C5", // 12 bright blue
        "#DF69BA", // 13 bright magenta
        "#35A77C", // 14 bright cyan
        "#829181", // 15 bright white
    ]
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Add `Klausemeister/Theme/EverforestPalette.swift` to the Klausemeister target under the "Theme" group.

- [ ] **Step 3: Build to verify data model compiles**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Theme/AppTheme.swift Klausemeister/Theme/EverforestPalette.swift
git commit -m "Add AppTheme enum and Everforest palette definitions"
```

---

### Task 3: Update GhosttyApp to support theming

**Files:**
- Modify: `Klausemeister/Terminal/GhosttyApp.swift`

The ghostty C API has no `ghostty_config_set` — colors must be loaded from a file via `ghostty_config_load_file`. We write a theme config file to Application Support, then load it after default files so theme colors override user defaults.

- [ ] **Step 1: Add theme config file writing method**

Add a method to GhosttyApp that writes a ghostty-format config file:

```swift
private static func writeThemeConfig(_ theme: AppTheme) -> String? {
    let colors = theme.colors
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("Klausemeister", isDirectory: true)

    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

    let configURL = appSupport.appendingPathComponent("theme.conf")

    var lines: [String] = []
    lines.append("background = \(colors.background.dropFirst())")
    lines.append("foreground = \(colors.foreground.dropFirst())")
    lines.append("cursor-color = \(colors.cursorColor.dropFirst())")
    lines.append("selection-background = \(colors.selectionBg.dropFirst())")
    lines.append("selection-foreground = \(colors.selectionFg.dropFirst())")
    for (i, hex) in colors.palette.enumerated() {
        lines.append("palette = \(i)=\(hex.dropFirst())")
    }

    let content = lines.joined(separator: "\n") + "\n"
    do {
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL.path
    } catch {
        return nil
    }
}
```

- [ ] **Step 2: Refactor init to accept a theme and extract runtime setup**

Replace the current `GhosttyApp` implementation. The key changes:
- `init()` calls a shared `setup(theme:)` method
- `rebuild(theme:)` tears down and re-creates with new config
- Runtime callbacks are extracted to a method for reuse

Replace the full contents of `GhosttyApp.swift`:

```swift
import AppKit
import GhosttyKit

@MainActor
final class GhosttyApp {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    private init() {
        ghostty_init(0, nil)
        setup(theme: nil)
    }

    func rebuild(theme: AppTheme) {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
        self.app = nil
        self.config = nil
        setup(theme: theme)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func setup(theme: AppTheme?) {
        let cfg = ghostty_config_new()!
        ghostty_config_load_default_files(cfg)

        if let theme, let path = Self.writeThemeConfig(theme) {
            path.withCString { ptr in
                ghostty_config_load_file(cfg, ptr)
            }
        }

        ghostty_config_finalize(cfg)
        self.config = cfg

        var runtime = makeRuntimeConfig()
        self.app = ghostty_app_new(&runtime, cfg)
    }

    private func makeRuntimeConfig() -> ghostty_runtime_config_s {
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let ref = ud
            DispatchQueue.main.async {
                let app = Unmanaged<GhosttyApp>.fromOpaque(ref).takeUnretainedValue()
                app.tick()
            }
        }
        runtime.action_cb = { _, _, _ in false }

        runtime.read_clipboard_cb = { ud, clipboard, state in
            guard let ud else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            guard let surface = view.surface else { return false }
            let content = NSPasteboard.general.string(forType: .string) ?? ""
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }

        runtime.confirm_read_clipboard_cb = { ud, content, state, request in
            guard let ud else { return }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            guard let surface = view.surface else { return }
            ghostty_surface_complete_clipboard_request(surface, content, state, true)
        }

        runtime.write_clipboard_cb = { ud, clipboard, contents, contentsLen, confirm in
            guard contentsLen > 0, let first = contents else { return }
            if let data = first.pointee.data {
                let s = String(cString: data)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }

        runtime.close_surface_cb = { ud, processAlive in }

        return runtime
    }

    private static func writeThemeConfig(_ theme: AppTheme) -> String? {
        let colors = theme.colors
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Klausemeister", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let configURL = appSupport.appendingPathComponent("theme.conf")

        var lines: [String] = []
        lines.append("background = \(colors.background.dropFirst())")
        lines.append("foreground = \(colors.foreground.dropFirst())")
        lines.append("cursor-color = \(colors.cursorColor.dropFirst())")
        lines.append("selection-background = \(colors.selectionBg.dropFirst())")
        lines.append("selection-foreground = \(colors.selectionFg.dropFirst())")
        for (i, hex) in colors.palette.enumerated() {
            lines.append("palette = \(i)=\(hex.dropFirst())")
        }

        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return configURL.path
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Terminal/GhosttyApp.swift
git commit -m "Add theme support to GhosttyApp with config file loading"
```

---

### Task 4: Update GhosttyAppClient dependency

**Files:**
- Modify: `Klausemeister/Dependencies/GhosttyAppClient.swift`

- [ ] **Step 1: Add rebuild method to GhosttyAppClient**

```swift
import Dependencies
import GhosttyKit

struct GhosttyAppClient: Sendable {
    var app: @Sendable @MainActor () -> ghostty_app_t?
    var tick: @Sendable @MainActor () -> Void
    var rebuild: @Sendable @MainActor (AppTheme) -> Void
}

extension GhosttyAppClient: DependencyKey {
    nonisolated static let liveValue = GhosttyAppClient(
        app: { GhosttyApp.shared.app },
        tick: { GhosttyApp.shared.tick() },
        rebuild: { theme in GhosttyApp.shared.rebuild(theme: theme) }
    )
    nonisolated static let testValue = GhosttyAppClient(
        app: { nil },
        tick: { },
        rebuild: { _ in }
    )
}

extension DependencyValues {
    var ghosttyApp: GhosttyAppClient {
        get { self[GhosttyAppClient.self] }
        set { self[GhosttyAppClient.self] = newValue }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Dependencies/GhosttyAppClient.swift
git commit -m "Add rebuild method to GhosttyAppClient for theme switching"
```

---

### Task 5: Add surface recreation to SurfaceStore and SurfaceManager

**Files:**
- Modify: `Klausemeister/Dependencies/SurfaceStore.swift`
- Modify: `Klausemeister/Dependencies/SurfaceManager.swift`

When the ghostty app is rebuilt, all existing surfaces are invalid. We need methods to destroy all surfaces and recreate them for existing tab IDs.

- [ ] **Step 1: Add destroyAll and recreateAll to SurfaceStore**

Add two methods to the `SurfaceStore` class:

```swift
func destroyAll() {
    surfaces.removeAll()
}

func recreateAll(ids: [UUID], app: ghostty_app_t) {
    for id in ids {
        let view = SurfaceView(frame: .zero)
        view.initializeSurface(app: app, workingDirectory: NSHomeDirectory())
        if view.surface != nil {
            surfaces[id] = view
        }
    }
}
```

- [ ] **Step 2: Add recreateAllSurfaces to SurfaceManager**

Add a new closure to the `SurfaceManager` struct:

```swift
struct SurfaceManager: Sendable {
    var createSurface: @Sendable @MainActor (UUID) -> Bool
    var destroySurface: @Sendable @MainActor (UUID) -> Void
    var focus: @Sendable @MainActor (UUID) async -> Bool
    var unfocus: @Sendable @MainActor (UUID) -> Void
    var recreateAllSurfaces: @Sendable @MainActor ([UUID]) -> Void
}
```

Update the `.live` factory to include the new closure:

```swift
extension SurfaceManager {
    static func live(surfaceStore: SurfaceStore, ghosttyApp: GhosttyAppClient) -> Self {
        SurfaceManager(
            createSurface: { id in
                guard let app = ghosttyApp.app() else { return false }
                return surfaceStore.create(id: id, app: app)
            },
            destroySurface: { id in
                surfaceStore.destroy(id: id)
            },
            focus: { id in
                await surfaceStore.focus(id)
            },
            unfocus: { id in
                surfaceStore.unfocus(id)
            },
            recreateAllSurfaces: { ids in
                surfaceStore.destroyAll()
                guard let app = ghosttyApp.app() else { return }
                surfaceStore.recreateAll(ids: ids, app: app)
            }
        )
    }
}
```

Update `liveValue` and `testValue`:

```swift
extension SurfaceManager: DependencyKey {
    nonisolated static let liveValue = SurfaceManager(
        createSurface: { _ in false },
        destroySurface: { _ in },
        focus: { _ in false },
        unfocus: { _ in },
        recreateAllSurfaces: { _ in }
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: { _ in true },
        destroySurface: { _ in },
        focus: { _ in true },
        unfocus: { _ in },
        recreateAllSurfaces: { _ in }
    )
}
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Dependencies/SurfaceStore.swift Klausemeister/Dependencies/SurfaceManager.swift
git commit -m "Add surface recreation support for theme switching"
```

---

### Task 6: Add themeChanged action to AppFeature

**Files:**
- Modify: `Klausemeister/AppFeature.swift`

- [ ] **Step 1: Add themeChanged action and handler**

Add to the `Action` enum:

```swift
case themeChanged(AppTheme)
```

Add to the `Reduce` body's switch, and add the `ghosttyApp` dependency:

```swift
@Dependency(\.surfaceManager) var surfaceManager
@Dependency(\.ghosttyApp) var ghosttyApp
@Dependency(\.uuid) var uuid
```

Add the case handler:

```swift
case let .themeChanged(theme):
    let tabIDs = state.tabs.map(\.id)
    let activeID = state.activeTabID
    return .run { _ in
        ghosttyApp.rebuild(theme)
        surfaceManager.recreateAllSurfaces(tabIDs)
        if let activeID {
            _ = await surfaceManager.focus(activeID)
        }
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/AppFeature.swift
git commit -m "Add themeChanged action to AppFeature"
```

---

### Task 7: Add Theme menu and wire up in KlausemeisterApp

**Files:**
- Modify: `Klausemeister/KlausemeisterApp.swift`

- [ ] **Step 1: Add @AppStorage and Theme menu**

Add `@AppStorage` property to `KlausemeisterApp`:

```swift
@AppStorage("selectedTheme") private var selectedTheme: AppTheme = .darkMedium
```

Note: `AppTheme` already conforms to `RawRepresentable` with `String` raw values, so `@AppStorage` works directly.

Add a `CommandMenu("Theme")` in the `commands` block, after the existing `CommandMenu("Tabs")`:

```swift
CommandMenu("Theme") {
    Section("Dark") {
        ForEach([AppTheme.darkHard, .darkMedium, .darkSoft]) { theme in
            Button {
                selectedTheme = theme
            } label: {
                if theme == selectedTheme {
                    Label(theme.displayName, systemImage: "checkmark")
                } else {
                    Text(theme.displayName)
                }
            }
        }
    }
    Section("Light") {
        ForEach([AppTheme.lightHard, .lightMedium, .lightSoft]) { theme in
            Button {
                selectedTheme = theme
            } label: {
                if theme == selectedTheme {
                    Label(theme.displayName, systemImage: "checkmark")
                } else {
                    Text(theme.displayName)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Inject theme environment and react to changes**

Add `.environment(\.themeColors, selectedTheme.colors)` and `.onChange(of: selectedTheme)` to the `WindowGroup`:

```swift
WindowGroup {
    TerminalContainerView(store: store, surfaceStore: surfaceStore)
}
.defaultSize(width: 900, height: 600)
.environment(\.themeColors, selectedTheme.colors)
.onChange(of: selectedTheme) { _, newTheme in
    store.send(.themeChanged(newTheme))
}
```

Note: `.environment()` must be on the `WindowGroup` scene, not on the view inside it.

- [ ] **Step 3: Apply initial theme at launch**

Update the `init()` to apply the initial theme to ghostty. Read the stored theme and pass it to `GhosttyApp.shared.rebuild`:

```swift
init() {
    let surfaceStore = SurfaceStore()
    self.surfaceStore = surfaceStore

    let initialTheme = AppTheme(
        rawValue: UserDefaults.standard.string(forKey: "selectedTheme") ?? ""
    ) ?? .darkMedium
    GhosttyApp.shared.rebuild(theme: initialTheme)

    self.store = Store(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.surfaceManager = .live(
            surfaceStore: surfaceStore,
            ghosttyApp: $0.ghosttyApp
        )
    }
}
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/KlausemeisterApp.swift
git commit -m "Add Theme menu with 6 Everforest variants"
```

---

### Task 8: Apply theme tints to views

**Files:**
- Modify: `Klausemeister/TerminalContainerView.swift`
- Modify: `Klausemeister/Views/SidebarView.swift`

- [ ] **Step 1: Add theme accent to TerminalContainerView**

Add the environment property:

```swift
@Environment(\.themeColors) private var themeColors
```

Add `.tint(themeColors.accentColor)` to the `NavigationSplitView`:

```swift
.tint(themeColors.accentColor)
```

- [ ] **Step 2: Add sidebar glass tint to SidebarView**

Add the environment property to `SidebarView`:

```swift
@Environment(\.themeColors) private var themeColors
```

Add `.glassEffect(.regular.tint(themeColors.accentColor))` to the new tab button's glass effect. Replace `.buttonStyle(.glass)` with:

```swift
.buttonStyle(.glass)
.tint(themeColors.accentColor)
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/TerminalContainerView.swift Klausemeister/Views/SidebarView.swift
git commit -m "Apply Everforest theme tints to app chrome"
```

---

### Task 9: Final build and integration verification

- [ ] **Step 1: Clean build**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister/.worktrees/alpha
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug clean build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Verify theme config file is written correctly**

Run the app briefly and check that the theme config file exists:

```bash
cat ~/Library/Application\ Support/Klausemeister/theme.conf
```

Expected output should contain ghostty config lines like:
```
background = 2d353b
foreground = d3c6aa
cursor-color = a7c080
...
palette = 0=343f44
palette = 1=e67e80
...
```

- [ ] **Step 3: Commit any final adjustments**

If any adjustments were needed, commit them. Otherwise, this step is a no-op.
