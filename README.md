# Klausemeister

A native macOS terminal + project management tool. Klausemeister combines a **libghostty-powered terminal** with a **Linear-backed kanban board** and **git worktree orchestration**, so the workflow of "pick a ticket → spawn a branch → open a terminal in that worktree → get work done" happens inside a single app.

## What's in the box

- **Terminal** — [libghostty](https://github.com/ghostty-org/ghostty) under the hood: GPU-rendered, fast, proper IME support. Ghostty does the emulation; Klausemeister provides the macOS shell.
- **Meister** — A kanban board that imports Linear issues, lets you drag cards between workflow states, and pushes status changes back to Linear via GraphQL.
- **Worktrees** — Create git worktrees per Linear issue, with automatic branch switching and an inbox → processing → outbox queue visualization. Assigning an issue to a worktree automatically switches that worktree's git branch.
- **Multi-repo aware** — Register multiple git repositories and organize worktrees under them.
- **Tab-based terminal shell** — Cmd+T for new tab, Cmd+1–9 to jump, Cmd+W to close, `\` to toggle the sidebar. Switch freely between the kanban board, a worktree detail view, and any terminal tab.

## Requirements

- macOS with Xcode 16 or newer
- [Homebrew](https://brew.sh) for the code-quality tools
- A Linear account (for the Meister/worktree features)

## Build & Run

```bash
# Clone
git clone https://github.com/selfishfishi/Klausemeister.git
cd Klausemeister

# Install formatting + lint tools
brew install swiftlint swiftformat

# Open in Xcode and hit ⌘R
open Klausemeister.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build
```

SPM dependencies resolve automatically when Xcode opens the project. The only external SPM dependency is `libghostty-spm`; GRDB and TCA are pulled in by the project.

## Development workflow

Before committing or opening a PR, run the Makefile targets:

```bash
make format    # swiftformat . — rewrites files in place
make lint      # swiftlint lint --strict — fails on any violation
```

Or both:

```bash
make format && make lint
```

`make lint` is strict and any violation will fail the build, so run it before pushing.

## Architecture

Klausemeister uses [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) for everything outside the terminal itself. Four strict layers: SwiftUI views → TCA reducers → `@Dependency` clients → external systems (SQLite/GRDB, Linear GraphQL, Keychain, git CLI, libghostty).

For the full architectural walkthrough with diagrams, see:

- **`architecture.md`** — Markdown with mermaid diagrams
- **`architecture.html`** — Standalone HTML with rendered SVG diagrams (open in any browser)

For AI-agent-specific guidance (including libghostty callback rules and layer discipline), see **`CLAUDE.md`**.

## Project tracking

Active work and backlog live in Linear:

https://linear.app/selfishfish/team/KLA

## License

TBD.
