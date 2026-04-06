# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What this project is

Klausemeister is a native macOS app that combines a **libghostty-powered terminal** with a **TCA-driven project management layer** for Linear issues, git worktrees, and a kanban board. It is a thin Swift shell over the libghostty C API, wrapped in a Composable Architecture state machine for everything outside the terminal itself.

For a full architectural walkthrough with diagrams, read `architecture.md` (or open `architecture.html` in a browser for the rendered version).

## Build & Run

Native macOS Xcode project. No `Package.swift` — everything is managed via `Klausemeister.xcodeproj`.

```bash
# Build via xcodebuild
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build

# Resolve SPM dependencies (if needed after clone)
xcodebuild -project Klausemeister.xcodeproj -resolvePackageDependencies
```

There are currently no tests.

## Code quality — Makefile targets

**Before committing or after completing any feature change**, run the two Makefile targets:

```bash
make format   # swiftformat . — rewrites files in place
make lint     # swiftlint lint --strict — fails on any violation
```

Or both in sequence:

```bash
make format && make lint
```

`make lint` uses strict mode and exits non-zero on any violation. **Do not open a PR with lint errors.** Both tools must be installed via Homebrew:

```bash
brew install swiftlint swiftformat
```

## Architecture Overview

The app has four layers, strictly ordered top to bottom:

```
UI (SwiftUI views)
    ↓
State (TCA reducers — @Reducer structs)
    ↓
Dependencies (@Dependency clients — structs of @Sendable closures)
    ↓
External systems (GRDB/SQLite, Linear GraphQL, Keychain, git CLI, libghostty)
```

**TCA feature hierarchy** (composition root is `AppFeature`):

```
AppFeature                    tabs, sidebar, detail-pane routing
├── MeisterFeature            kanban board, Linear issue import/refresh
├── WorktreeFeature           worktrees, queues (inbox→processing→outbox), repos
└── LinearAuthFeature         PKCE OAuth flow, user profile
```

Cross-feature events use **TCA delegate actions** intercepted by `AppFeature`'s parent `Reduce` — features never reach into each other's state directly. Example: Meister emits `.delegate(.issueAssignedToWorktree)`, `AppFeature` catches it and re-dispatches as `.worktree(.issueAssignedToWorktree)`.

### Key modules

**App shell + routing:**
- `Klausemeister/KlausemeisterApp.swift` — `@main` entry, `WindowGroup`, `.commands` keyboard shortcuts (Cmd+T, Cmd+W, Cmd+1–9, etc.)
- `Klausemeister/AppFeature.swift` — Root reducer, holds `tabs`, `activeTabID`, `showMeister`, composes child features via `Scope`
- `Klausemeister/TerminalContainerView.swift` — Three-way detail-pane switch (Meister / WorktreeDetail / Terminal)

**TCA features:**
- `Klausemeister/Linear/MeisterFeature.swift` — Kanban board state machine
- `Klausemeister/Worktrees/WorktreeFeature.swift` — Worktree + queue state machine
- `Klausemeister/Linear/LinearAuthFeature.swift` — OAuth flow

**Dependency clients** (all under `Klausemeister/Dependencies/`):
- `DatabaseClient` — GRDB queue + `imported_issues` CRUD
- `WorktreeClient` — worktree/repository/queue-item CRUD (shares DB queue)
- `LinearAPIClient` — Linear GraphQL
- `OAuthClient` — PKCE flow
- `KeychainClient` — access/refresh token storage
- `GitClient` — `/usr/bin/git` subprocess wrapper
- `SurfaceManager` + `GhosttyAppClient` — libghostty lifecycle and surface focus

**Persistence** (`Klausemeister/Database/`): GRDB `FetchableRecord`/`PersistableRecord` structs + `DatabaseMigrations.swift` (sequential versioned migrations).

**Terminal stack** (`Klausemeister/Terminal/`): `SurfaceView` (NSView + Metal), `GhosttyApp` (@MainActor singleton over `ghostty_app_t`), `KeyMapping` (NSEvent → ghostty C structs translation).

## Layer discipline

These rules keep layers isolated. Violations were identified in an architecture review (see KLA-60 through KLA-63).

- **Views never use `@Dependency`.** All side effects go through a store action.
- **Reducers never `import SwiftUI` or `import AppKit`.** They deal in value types only.
- **Dependency clients never `import ComposableArchitecture`.** They are framework-agnostic structs of closures.
- **Persistence records (`*Record` types) stay below the dependency boundary.** Client live implementations should map `Record → Domain` internally and return domain types (`LinearIssue`, `Worktree`, `Repository`). Raw records should not appear in reducer action enums. (This is currently violated — see KLA-60.)
- **No direct singleton access outside the dependency layer.** `GhosttyApp.shared` is only touched inside `GhosttyAppClient.liveValue` and the `GhosttyApp` file itself; callers use `@Dependency(\.ghosttyApp)`.
- **Cross-feature view dependencies** (e.g., `KanbanIssueCardView` taking a `[Worktree]` parameter) should go through shared domain types in a `Models/` layer, not through another feature's file. (See KLA-62.)

When adding a new feature, always ask: "which layer owns this code, and does it only talk to the layer directly below it?"

## TCA conventions

- **State is `@ObservableState`** on every feature; views use `StoreOf<Feature>` or `@Bindable var store`. No `WithViewStore`.
- **Side effects live in `Effect.run`** — reducer bodies are synchronous state mutation only.
- **Actions describe events, not commands** — `buttonTapped`, `dataLoaded`, not `setLoading(true)`.
- **Delegate actions** (`.delegate(.event)`) are the only mechanism for cross-feature communication. Parent reducers pattern-match on `case let .child(.delegate(...))`.
- **Presentation components** (`IssueCardView`, `SwimlaneRowView`) take plain values and closures — no store dependency — and are reused across contexts.
- **Dependency clients** are structs of closures, not protocols. Test values use `unimplemented(...)` to loudly fail on unstubbed paths.
- **`BindingReducer()` before `Reduce`** when using `BindableAction`.

## Terminal stack (libghostty)

Klausemeister embeds **libghostty** (Zig) for VT emulation, PTY management, font shaping, and Metal rendering. The Swift layer only provides macOS integration: window management, input event translation, and surface hosting.

```
SwiftUI (KlausemeisterApp / TerminalContainerView)
    ↓ NSViewRepresentable bridge
AppKit + Metal (SurfaceView — NSView with CAMetalLayer)
    ↓ C FFI calls
libghostty C API (GhosttyKit framework via SPM)
    ↓
Zig core (VT emulation, rendering, PTY, fonts)
```

**Keyboard input pipeline:** `NSEvent` → `SurfaceView.keyDown()` → `KeyMapping.translateKeyEvent()` → `ghostty_surface_key()` for raw input, then `interpretKeyEvents()` → `NSTextInputClient` for IME composition. `performKeyEquivalent()` handles key binding detection.

### Why no App Sandbox

PTY creation requires subprocess spawning, which the sandbox blocks. Hardened runtime is still enabled.

## libghostty API verification

Before writing or modifying any `ghostty_*` C API call, **always verify the function signature and callback contract** against upstream docs. Use the context7 MCP:

1. `resolve-library-id` with `libraryName: "libghostty"` → use `/websites/libghostty_tip_ghostty`
2. `query-docs` with that library ID and your specific question

The ghostty C API has subtle conventions (different userdata per callback, opaque state tokens that must be passed through) that are easy to get wrong. The compiler will not catch type mismatches because everything is `void*`.

Reference: the official macOS app at `https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Ghostty/Ghostty.App.swift` is the canonical implementation of all runtime callbacks.

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

## External dependencies

Single SPM dependency: **libghostty-spm**, which wraps the libghostty C library. Provides `GhosttyKit` and `GhosttyTerminal` frameworks. All `ghostty_*` calls go through this package's C headers.

Non-SPM dependencies pulled in by the Xcode project:
- **GRDB** — SQLite persistence (used by `DatabaseClient` and `WorktreeClient`)
- **swift-composable-architecture** — TCA
- **swift-dependencies** — `@Dependency` machinery

## Working in git worktrees

This repo is frequently driven from git worktrees under `.worktrees/<name>`. When the session cwd is inside a worktree:

- **Do not `cd` to the parent repo path.** Each worktree has its own HEAD; commands run against the parent affect a different working tree that the user cannot see.
- Use `git -C <path>` explicitly if you genuinely need to target a different working tree.
- When writing files, use the session cwd — not the parent repo path.
- Verify with `git worktree list` if unsure which branch a path is on.

## Swift conventions

- Swift Concurrency with `@MainActor` default isolation and approachable concurrency mode.
- Minimal SwiftUI — the rendering-heavy terminal is an `NSView`, not a SwiftUI view. SwiftUI is only the outermost shell plus the Meister/Worktree panels.
- C interop is direct (no wrapper classes around ghostty types) — opaque handles like `ghostty_app_t` and `ghostty_surface_t` are used as-is.

## Development methodology

The project follows spec-driven development. Research and design docs live in `.notes/` (git-ignored). Non-trivial features should have design docs before implementation.

## Project tracking

Linear team: https://linear.app/selfishfish/team/KLA

Issue states: Backlog → Definition → Todo → Spec → In Progress → In Review → Testing → Done
