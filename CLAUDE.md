# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native macOS app built with Xcode. No Package.swift — the project is managed entirely via `Klausemeister.xcodeproj`.

```bash
# Build
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build

# Resolve SPM dependencies (if needed after clone)
xcodebuild -project Klausemeister.xcodeproj -resolvePackageDependencies
```

There are currently no tests.

## Architecture

Klausemeister is a **thin native Swift shell over libghostty's C API**. The terminal emulation, PTY management, font shaping, and GPU rendering are all handled by libghostty (Zig). The Swift layer provides macOS integration: window management, input event translation, and Metal surface hosting.

```
SwiftUI (KlausemeisterApp / TerminalContainerView)
    ↓ NSViewRepresentable bridge
AppKit + Metal (SurfaceView — NSView with CAMetalLayer)
    ↓ C FFI calls
libghostty C API (GhosttyKit framework via SPM)
    ↓
Zig core (VT emulation, rendering, PTY, fonts)
```

### Key modules

- **`Klausemeister/KlausemeisterApp.swift`** — @main entry, WindowGroup setup.
- **`Klausemeister/TerminalContainerView.swift`** — NSViewRepresentable bridging SurfaceView into SwiftUI.
- **`Klausemeister/Terminal/GhosttyApp.swift`** — @MainActor singleton managing libghostty lifecycle (init, config, clipboard callbacks, tick loop).
- **`Klausemeister/Terminal/SurfaceView.swift`** — Core NSView: Metal rendering, full keyboard pipeline (NSTextInputClient/IME), mouse events, focus management. This is where most platform integration lives.
- **`Klausemeister/Terminal/KeyMapping.swift`** — Pure translation layer: NSEvent modifier flags and key codes → ghostty C structs.

### Keyboard input pipeline

NSEvent → `SurfaceView.keyDown()` → `KeyMapping.translateKeyEvent()` → `ghostty_surface_key()` for raw input, then `interpretKeyEvents()` → NSTextInputClient for IME composition. `performKeyEquivalent()` handles key binding detection.

### Why no App Sandbox

PTY creation requires subprocess spawning, which the sandbox blocks. Hardened runtime is still enabled.

## Dependencies

Single external dependency: **libghostty-spm** (Swift Package Manager), which wraps the libghostty C library. Provides `GhosttyKit` and `GhosttyTerminal` frameworks. All `ghostty_*` function calls go through this package's C headers.

## libghostty API verification

Before writing or modifying any `ghostty_*` C API call, **always verify the function signature and callback contract** against the upstream docs. Use context7 MCP:

1. `resolve-library-id` with `libraryName: "libghostty"` → use `/websites/libghostty_tip_ghostty`
2. `query-docs` with that library ID and your specific question

The ghostty C API has subtle conventions (different userdata per callback, opaque state tokens that must be passed through) that are easy to get wrong. The compiler won't catch type mismatches because everything is `void*`.

Also reference: the official macOS app at `https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Ghostty/Ghostty.App.swift` is the canonical implementation of all runtime callbacks.

## libghostty callback rules

Runtime callbacks have **two different userdata types**. Getting this wrong compiles fine (both are `void*`) but crashes at runtime:

| Callback | Receives | Cast to |
|----------|----------|---------|
| `wakeup_cb` | `runtime.userdata` (app-level) | `GhosttyApp` |
| `action_cb` | `ghostty_app_t` directly | n/a |
| `read_clipboard_cb` | `surface_config.userdata` (surface-level) | `SurfaceView` |
| `confirm_read_clipboard_cb` | surface userdata | `SurfaceView` |
| `write_clipboard_cb` | surface userdata | `SurfaceView` |
| `close_surface_cb` | surface userdata | `SurfaceView` |

`ghostty_surface_complete_clipboard_request(surface, content, state, confirmed)` — first arg is the `ghostty_surface_t` from `SurfaceView.surface`, third arg is the opaque `state` pointer from the callback. Never swap them.

Full API reference: `.notes/libghostty.md`

## Development methodology

The project follows spec-driven development. Research and design docs live in `.notes/` (git-ignored). Non-trivial features should have design docs before implementation.

## Project tracking

Linear team: https://linear.app/selfishfish/team/KLA

Issue states: Backlog (unrefined idea) → Definition (requirements being written) → Todo (ready to pick up) → Spec (writing a spec) → In Progress (implementing) → In Review (PR review) → Testing (acceptance testing) → Done

## Swift conventions

- Swift Concurrency with `@MainActor` default isolation and approachable concurrency mode.
- Minimal SwiftUI — the rendering-heavy terminal is an NSView, not a SwiftUI view. SwiftUI is only the outermost shell.
- C interop is direct (no wrapper classes around ghostty types) — opaque handles like `ghostty_app_t` and `ghostty_surface_t` are used as-is.

## Code quality

**Before committing or after completing a feature change**, run:

```bash
make format && make lint
```

`make format` runs SwiftFormat and rewrites files in place. `make lint` runs SwiftLint in strict mode and exits non-zero on any violation. Fix all lint errors before opening a PR.

Both tools must be installed via Homebrew:

```bash
brew install swiftlint swiftformat
```
