# Klausemeister

A native macOS **terminal + project-management tool + agent orchestrator**, built around a simple idea: the path from *"here's a Linear ticket"* to *"PR merged"* should be one app — ideally one keyboard shortcut.

Klausemeister pairs a [libghostty](https://github.com/ghostty-org/ghostty)-powered terminal with a Linear-backed kanban board, git worktree management, and an MCP server that can drive headless [Claude Code](https://claude.ai/code) "meister" agents through a formal workflow state machine. Pick a ticket, spawn a branch + worktree + tmux session, hand it to a meister, watch it cook.

## At a glance

The main window hosts three panels that share one detail pane:

- **Sidebar** — repositories, worktrees (with per-worktree queues), terminal tabs, and meister status dots.
- **Detail pane** — routes to one of: the kanban board (**Meister**), a single worktree's swimlane (**Worktree detail**), or a live terminal tab.
- **Inspector** (optional, Cmd+L) — Linear ticket details, including Markdown description, labels, and state, rendered inline.

## Feature set

### Terminal

- **GPU-rendered** via libghostty's Metal backend — the same VT emulator, font shaper, and PTY stack as [Ghostty.app](https://ghostty.org). Klausemeister is a thin Swift shell over `libghostty`; all the fast stuff is Zig.
- **Tabs and window-level IME** — full `NSTextInputClient` bridging for CJK/emoji composition. Key bindings go through `performKeyEquivalent` so the menu bar and the terminal don't fight over shortcuts.
- **Tmux 1:1 with worktrees** — every worktree gets its own tmux session. Opening a worktree terminal attaches to that session; closing the tab detaches but keeps the session alive.
- **Live config hot-reload** — theme switches re-apply libghostty config in place without destroying the surface.

### Meister — the kanban board

- **Linear issues imported via GraphQL** and cached in SQLite (GRDB). Drag cards between workflow states; status changes round-trip back to Linear.
- **Team filter** — pick which Linear teams show up in the board.
- **State mapping** — configure which Linear workflow state on each team maps to which kanban column (Backlog / Definition / Todo / Spec / In Progress / In Review / Testing / Done).

### Worktrees

- **Per-issue git worktrees** — assigning an issue to a worktree creates a branch and switches the worktree to it. All through `/usr/bin/git` — no libgit2, no surprises.
- **Inbox → Processing → Outbox queues** — each worktree has three swimlanes. Pull an issue into *Processing* to start work; push it to *Outbox* when done. Returning an issue from a worktree puts it back on the kanban board in the correct column.
- **Multi-repo aware** — register several repositories; organize worktrees under them.
- **Schedule Gantt overlay** — visualize scheduled work across worktrees as a gantt strip (MVP).
- **Swimlane actions** — inline buttons per lane to advance the workflow (Define / Execute / Review / Open PR / Babysit / Push) via slash commands injected into the worktree's tmux session.

### Meister loop (autonomous agents)

Klausemeister can spawn a headless Claude Code — a "**meister**" — in each worktree's tmux session. The meister loads the [`klause-workflow`](klause-workflow/README.md) plugin and drives the ticket through a formal state machine:

```
Pull → Define → Execute → Review → Open PR → Babysit → Push
```

Each transition is a slash command (`/klause-workflow:klause-define`, etc.) that maps to exactly one edge in `ProductStateMachine`. The app coordinates meisters through an **in-process MCP server** (Unix socket) and a **shim** (`klause-mcp-shim`) that bridges Claude Code's stdio transport to the socket. The shim forwards `getNextItem`, `reportProgress`, `reportActivity`, `completeItem`, etc. straight into the TCA store.

This makes the whole board "pilotable" — kick a card over to a worktree, start a meister, and it will work the ticket end-to-end unless you intervene.

### Command palette, shortcuts, inspector

- **Command palette** (Ctrl+P, or Cmd+Shift+P for VS Code muscle memory) — fuzzy-search every `AppCommand`. Runs the action directly.
- **Shortcut Center** (Cmd+,) — view and customize every key binding. Bindings are persisted in `UserDefaults` and re-read at session start.
- **Worktree switcher** (Ctrl+K) — quick-jump between Meister and any worktree.
- **Inspector** (Cmd+L) — slide-out ticket inspector with Markdown-rendered description.
- **Debug panel** (Cmd+Shift+D) — MCP server state, active shim discovery, connection diagnostics.

### Themes

Six theme families with multiple variants each, selectable from the Theme menu:

- **Everforest** (default) — Dark Hard / Medium / Soft + Light variants
- **Gruvbox** — same 6-variant matrix
- **Catppuccin** — Latte / Frappé / Macchiato / Mocha
- **Tokyo Night** — Night / Storm / Moon / Day
- **Rosé Pine** — Main / Moon / Dawn
- **Kanagawa** — Wave / Dragon / Lotus

Theme changes hot-reload the terminal palette and update every SwiftUI surface simultaneously.

## Keyboard shortcuts

Defaults below — all are rebindable via the Shortcut Center (Cmd+,).

| Shortcut | Action |
|---|---|
| Cmd+T | New terminal tab |
| Cmd+W | Close current tab |
| Cmd+1 … Cmd+9 | Jump to worktree by sidebar position |
| Cmd+R | Toggle sidebar |
| Cmd+L | Toggle inspector |
| Cmd+, | Open Shortcut Center |
| Ctrl+P / Cmd+Shift+P | Command palette |
| Ctrl+K | Worktree switcher |
| Cmd+Shift+D | Toggle debug panel |

## Requirements

- macOS with Xcode 16 or newer
- [Homebrew](https://brew.sh) for `swiftlint` + `swiftformat`
- A Linear account (for kanban / worktree features)
- `tmux` on `PATH` (for per-worktree terminal sessions)
- Optional: `gh` CLI if you want the meister loop's `/klause-open-pr` + `/klause-babysit` to create and merge PRs on your behalf

## Build & run

```bash
# Clone
git clone https://github.com/selfishfishi/Klausemeister.git
cd Klausemeister

# Install lint / format tooling
brew install swiftlint swiftformat

# Open in Xcode and ⌘R
open Klausemeister.xcodeproj
```

SPM dependencies resolve automatically when Xcode opens the project. The only external SPM dep is `libghostty-spm`; GRDB, TCA, and `swift-dependencies` are pulled in by the project.

From the command line:

```bash
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build
```

### Why no App Sandbox?

PTY creation needs subprocess spawning, which the App Sandbox blocks. Hardened runtime is still enabled.

## Development workflow

Before opening a PR, run both Makefile targets:

```bash
make format && make lint
```

`make lint` is strict (`swiftlint lint --strict`) — any violation fails. `make format` rewrites in place. Do not push with lint errors.

## Architecture

Four strict layers, top → bottom:

```
SwiftUI views
    ↓
TCA reducers (@Reducer structs)
    ↓
@Dependency clients (structs of @Sendable closures)
    ↓
External systems (GRDB/SQLite, Linear GraphQL, Keychain, git, tmux, libghostty, MCP socket)
```

Cross-feature events are TCA **delegate actions** intercepted by `AppFeature`. Features never reach into each other's state.

For the full walkthrough — data model, MCP plumbing, libghostty bridge, runtime routing — see:

- **[`architecture.md`](architecture.md)** — with mermaid diagrams
- **[`architecture.html`](architecture.html)** — rendered SVG, open in any browser
- **[`CLAUDE.md`](CLAUDE.md)** — AI-agent conventions, layer rules, libghostty callback rules

## Companion projects in this repo

- **[`klause-workflow/`](klause-workflow/)** — Claude Code plugin shipped with the app. Provides the slash commands (`/klause-pull`, `/klause-execute`, `/klause-open-pr`, …) that drive the meister loop, plus the `open-pr` skill.
- **`klause-mcp-shim/`** — tiny stdio↔Unix-socket bridge. Claude Code speaks MCP over stdio; Klausemeister hosts the MCP server on a socket. The shim glues them together and carries the `KLAUSE_WORKTREE_ID` env var through so the server knows which worktree is calling.

## Project tracking

Active work and backlog live in Linear:

https://linear.app/selfishfish/team/KLA

## License

TBD.
