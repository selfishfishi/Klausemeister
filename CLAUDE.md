# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What this project is

Klausemeister is a native macOS app that combines a **libghostty-powered terminal** with a **TCA-driven project-management layer** (Linear issues, git worktrees, kanban), a **command palette / shortcut-center UX shell**, and an **in-process MCP server** that orchestrates headless Claude Code "meister" agents running in per-worktree tmux sessions. It is a thin Swift shell over the libghostty C API, wrapped in Composable Architecture for everything else.

For the user-facing overview and feature list, see `README.md`.
For the full architectural walkthrough with diagrams, read `architecture.md` (or open `architecture.html` in a browser for the rendered version).

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
AppFeature                         tabs, sidebar, inspector, detail-pane routing
├── MeisterFeature                 kanban board, Linear issue import/refresh
├── WorktreeFeature                worktrees, queues (inbox→processing→outbox), repos, schedule
├── LinearAuthFeature              PKCE OAuth flow, user profile
├── StatusBarFeature               bottom status bar
├── DebugPanelFeature              MCP diagnostics sheet
├── TeamSettingsFeature (@Presents) team filter + state mapping
├── CommandPaletteFeature          fuzzy-searchable command runner
├── ShortcutCenterFeature (@Presents) customizable key bindings
└── WorktreeSwitcherFeature        quick-switch overlay
```

Cross-feature events use **TCA delegate actions** intercepted by `AppFeature`'s parent `Reduce` — features never reach into each other's state directly. Example: Meister emits `.delegate(.issueAssignedToWorktree)`, `AppFeature` catches it and re-dispatches as `.worktree(.issueAssignedToWorktree)`.

### Key modules

**App shell + routing:**
- `Klausemeister/KlausemeisterApp.swift` — `@main` entry, `WindowGroup`, `.commands` keyboard shortcuts (wired through `AppCommand` + `KeyBindingsClient`)
- `Klausemeister/AppFeature.swift` — Root reducer, holds `tabs`, `activeTabID`, `showMeister`, `inspector*`, `presentedScheduleId`, composes child features via `Scope`
- `Klausemeister/TerminalContainerView.swift` — Three-way detail-pane switch (Meister / WorktreeDetail / Terminal)

**TCA features:**
- `Klausemeister/Linear/MeisterFeature.swift` — Kanban board state machine
- `Klausemeister/Linear/StateMappingFeature.swift` + `TeamSettingsFeature.swift` — Team-to-kanban column mapping config
- `Klausemeister/Worktrees/WorktreeFeature.swift` — Worktree + queue state machine, schedule overlay
- `Klausemeister/Linear/LinearAuthFeature.swift` — OAuth flow
- `Klausemeister/CommandPalette/CommandPaletteFeature.swift` — Fuzzy command search + execution
- `Klausemeister/ShortcutCenter/ShortcutCenterFeature.swift` — Rebindable keyboard shortcuts UI
- `Klausemeister/WorktreeSwitcher/WorktreeSwitcherFeature.swift` — Quick-switcher palette
- `Klausemeister/StatusBar/StatusBarFeature.swift` — Bottom bar
- `Klausemeister/Debug/DebugPanelFeature.swift` — MCP shim diagnostics
- `Klausemeister/Inspector/` — Linear ticket detail pane (`TicketInspectorView`, `InspectorModels`, `MarkdownTextView`)

**Workflow layer** (`Klausemeister/Workflow/`):
- `ProductStateMachine.swift` — `WorkflowCommand` (`.define`, `.execute`, `.review`, `.openPR`, `.babysit`, `.complete`, `.pull`, `.push`) and the (kanban, worktree) transition table. The swimlane UI and the meister loop both consult this.
- `QueuePosition.swift` — `inbox` / `processing` / `outbox`.

**MCP server** (`Klausemeister/MCP/`):
- `MCPSocketListener.swift` — Hosts a Unix-socket MCP server inside the app; `klause-mcp-shim` clients (one per Claude Code session) connect and forward JSON-RPC.
- `SocketTransport.swift` + `HelloFrame.swift` — transport framing + handshake (identity check via `KLAUSE_MEISTER`, `KLAUSE_WORKTREE_ID`).
- `ToolHandlers.swift`, `ScheduleToolHandlers.swift`, `ToolHandlers+reportActivity.swift` — business-logic tool handlers returning a plain `ToolResult`; the listener maps to the MCP SDK types.
- `MCPServerEvent.swift` + `WorkflowStateResolver.swift` — event bridge back to `AppFeature` and state-machine resolution.

**Dependency clients** (all under `Klausemeister/Dependencies/`):
- `DatabaseClient` — GRDB queue + `imported_issues` CRUD
- `WorktreeClient` — worktree/repository/queue-item CRUD (shares DB queue)
- `LinearAPIClient` — Linear GraphQL
- `OAuthClient` — PKCE flow
- `KeychainClient` — access/refresh token storage
- `GitClient` — `/usr/bin/git` subprocess wrapper
- `GHClient` — `gh` CLI wrapper (PR creation / merge)
- `TmuxClient` — `tmux` subprocess wrapper, session lifecycle bound 1:1 to worktrees
- `MeisterClient` — spawns/monitors meister Claude Code processes inside tmux windows
- `MeisterStatusClient` — reads meister activity state
- `MCPServerClient` — starts the in-process MCP server, exposes an `AsyncStream` of events, discovers active shims
- `ActionRegistry` — central registry of `AppCommand` → reducer action mappings (used by command palette + shortcut center)
- `KeyBindingsClient` — load/save user-customized key bindings
- `StateMappingClient` — persists team→column mapping
- `UserDefaultsClient`, `PasteboardClient`, `FolderPickerClient` — small OS-integration clients
- `SurfaceManager` + `SurfaceStore` + `GhosttyAppClient` — libghostty lifecycle and surface focus

**Persistence** (`Klausemeister/Database/`): GRDB `FetchableRecord`/`PersistableRecord` structs + `DatabaseMigrations.swift` (sequential versioned migrations).

**Terminal stack** (`Klausemeister/Terminal/`): `SurfaceView` (NSView + Metal), `GhosttyApp` (@MainActor singleton over `ghostty_app_t`), `KeyMapping` (NSEvent → ghostty C structs translation), `MouseCursorMapping`.

**Keyboard shortcuts** (`Klausemeister/Shortcuts/`): `AppCommand` enum is the single source of truth for every rebindable command (displayName, helpText, category, defaultBinding). `View+KeyboardShortcut.swift` wires SwiftUI `.keyboardShortcut` to `[AppCommand: KeyBinding]`.

**Theme** (`Klausemeister/Theme/`): `AppTheme` with six families (Everforest, Gruvbox, Catppuccin, Tokyo Night, Rosé Pine, Kanagawa). Switching themes hot-reloads libghostty config without tearing down the surface.

**Companion targets** (outside the main app target):
- `klause-workflow/` — Claude Code plugin (slash commands + meister-loop skill)
- `klause-mcp-shim/` — tiny executable that bridges Claude Code's stdio MCP transport to Klausemeister's Unix-socket server

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

## Workflow state machine + meister loop

`Klausemeister/Workflow/ProductStateMachine.swift` defines `WorkflowCommand` and the allowed `(KanbanState, WorktreePosition) → (KanbanState, WorktreePosition)` transitions. Each command maps to exactly one edge; callers (the swimlane UI, the MCP server, the meister's slash commands) all consult the same table.

Each `WorkflowCommand.slashCommand` is the namespaced command (`/klause-workflow:klause-define`, etc.) injected via `tmux send-keys` into a worktree's meister Claude Code session.

The **meister loop** — how autonomous Claude Code agents drive tickets to PR — is documented in `klause-workflow/CLAUDE.md`. When adding or changing a workflow command, update **all four** call sites in lockstep: `ProductStateMachine`, the MCP tool handler, the slash-command markdown in `klause-workflow/commands/`, and the swimlane button in `Klausemeister/Worktrees/SwimlaneAdvanceButton.swift`.

## MCP server

Klausemeister hosts an **in-process MCP server over a Unix socket** (`MCPSocketListener`). Each meister Claude Code connects through `klause-mcp-shim`, which bridges stdio ↔ socket and passes through the `KLAUSE_WORKTREE_ID` env var as part of the handshake (`HelloFrame`). The server uses that ID to route tool calls to the right worktree.

Tool handlers (`Klausemeister/MCP/ToolHandlers.swift`) are **free functions that return `ToolResult`** and resolve their dependencies via `@Dependency` at call time. They do **not** import the MCP SDK — `MCPSocketListener` translates between `ToolResult` and the SDK's `CallTool.Result`. This keeps the handlers unit-testable with `withDependencies` + `unimplemented(...)` test values.

`MCPServerClient.events()` returns a **single-consumer** `AsyncStream` of `MCPServerEvent`. Only `AppFeature.onAppear` should consume it — forking a second `for await` loop will race and drop events.

## External dependencies

Single SPM dependency: **libghostty-spm**, which wraps the libghostty C library. Provides `GhosttyKit` and `GhosttyTerminal` frameworks. All `ghostty_*` calls go through this package's C headers.

Non-SPM dependencies pulled in by the Xcode project:
- **GRDB** — SQLite persistence (used by `DatabaseClient` and `WorktreeClient`)
- **swift-composable-architecture** — TCA
- **swift-dependencies** — `@Dependency` machinery
- **MCP Swift SDK** — JSON-RPC + tool protocol for the in-process MCP server

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
