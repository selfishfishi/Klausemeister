# Klausemeister Architecture

Klausemeister is a native macOS app that combines a **libghostty-powered terminal** with a **TCA-driven project management layer** (Linear issues, git worktrees, kanban board). The app is a thin Swift shell over libghostty's C API for terminal emulation, wrapped in a Composable Architecture state machine for everything else.

## Layer Overview

```mermaid
flowchart TB
    subgraph UI["UI Layer — SwiftUI"]
        TCV[TerminalContainerView]
        SV[SidebarView]
        MTV[MeisterTabView]
        WDV[WorktreeDetailView]
        TCO[TerminalContentView]
    end

    subgraph TCA["State Layer — TCA Reducers"]
        AF[AppFeature]
        MF[MeisterFeature]
        WF[WorktreeFeature]
        LAF[LinearAuthFeature]
    end

    subgraph Deps["Dependency Clients — @Dependency"]
        DBC[DatabaseClient]
        WC[WorktreeClient]
        LAC[LinearAPIClient]
        OAC[OAuthClient]
        KC[KeychainClient]
        GC[GitClient]
        SM[SurfaceManager]
        GAC[GhosttyAppClient]
    end

    subgraph External["External Systems"]
        GRDB[(GRDB / SQLite)]
        Linear[Linear GraphQL API]
        Keychain[macOS Keychain]
        Git[git CLI]
        Ghostty[libghostty C API]
    end

    UI --> TCA
    TCA --> Deps
    DBC --> GRDB
    WC --> GRDB
    LAC --> Linear
    OAC --> Linear
    KC --> Keychain
    GC --> Git
    SM --> Ghostty
    GAC --> Ghostty
```

Everything above the Dependencies layer is pure Swift value types. All I/O, process spawning, and C FFI happens inside dependency clients, keeping reducers deterministic and testable.

## TCA Feature Hierarchy

```mermaid
flowchart TD
    AF[AppFeature<br/>tabs, sidebar, routing]
    MF[MeisterFeature<br/>kanban board, issue import]
    WF[WorktreeFeature<br/>worktrees, queues, repos]
    LAF[LinearAuthFeature<br/>OAuth flow, user profile]

    AF -->|Scope| MF
    AF -->|Scope| WF
    AF -->|Scope| LAF
```

`AppFeature` is the composition root. It owns top-level UI state (tab list, sidebar visibility, active tab, Meister/worktree routing) and composes the three child reducers via `Scope`. It also forwards tab keyboard shortcuts (Cmd+1–9) and orchestrates `SurfaceManager` focus lifecycle as the user switches between terminal tabs, the kanban board, and worktree detail views.

## Cross-Feature Coordination

Features never reach into each other's state directly. Cross-feature events use **TCA delegate actions** that the parent reducer (`AppFeature`) intercepts and re-dispatches to the sibling feature.

```mermaid
sequenceDiagram
    participant View as Kanban Card
    participant MF as MeisterFeature
    participant AF as AppFeature
    participant WF as WorktreeFeature
    participant DB as GRDB

    Note over View,DB: Assigning an issue to a worktree

    View->>MF: .assignIssueToWorktree(issue, worktreeId)
    MF->>MF: state.removeIssueFromAllColumns(issue.id)
    MF-->>AF: .delegate(.issueAssignedToWorktree)
    AF->>WF: .issueAssignedToWorktree(worktreeId, issue)
    WF->>WF: state.worktrees[wt].inbox.append(issue)
    WF->>DB: worktreeClient.assignIssueToWorktree
    WF->>DB: gitClient.switchBranch

    Note over View,DB: Returning an issue to Meister

    View->>WF: .issueReturnedToMeister(issueId, worktreeId)
    WF->>WF: remove from inbox/processing/outbox
    WF->>DB: findQueueItemId + removeFromQueue
    WF-->>AF: .delegate(.issueReturnedToMeister)
    AF->>MF: .issueReturnedFromWorktree(issue)
    MF->>MF: re-insert into correct column by statusId
```

Both directions keep state **immediately consistent** via optimistic mutations, then persist asynchronously. Errors roll back in failure actions.

## Dependency Clients

All external systems are accessed via TCA `@Dependency` clients. Each is a `struct` of `@Sendable` closures with a `liveValue` and a `testValue` that uses `unimplemented(...)`.

| Client | Purpose | Backing |
|---|---|---|
| `DatabaseClient` | GRDB queue + imported issue CRUD + filtered queries | SQLite via GRDB |
| `WorktreeClient` | Worktree/repository/queue-item CRUD | Same DB queue |
| `LinearAPIClient` | Linear GraphQL (issues, workflow states, updates) | `URLSession` + bearer token |
| `OAuthClient` | PKCE OAuth flow for Linear login | `NSWorkspace.open` + callback URL stream |
| `KeychainClient` | Access/refresh token storage | Keychain Services |
| `GitClient` | `git worktree add/remove`, branch switching | `/usr/bin/git` subprocess |
| `SurfaceManager` | Create/destroy/focus terminal surfaces | `SurfaceStore` + libghostty |
| `GhosttyAppClient` | `ghostty_app_t` lifecycle | libghostty C API |

`DatabaseClient` and `WorktreeClient` share a single `DatabaseQueue` — `WorktreeClient.liveValue` pulls it from `databaseClient.getDbQueue()` at initialization, so all writes serialize through one connection.

## Data Model

GRDB schema is defined in `DatabaseMigrations.swift` with sequential versioned migrations:

```mermaid
erDiagram
    repositories ||--o{ worktrees : "has"
    worktrees ||--o{ worktree_queue_items : "owns"
    imported_issues ||--o{ worktree_queue_items : "queued as"

    repositories {
        text repoId PK
        text name
        text path
        text createdAt
        int sortOrder
    }

    worktrees {
        text worktreeId PK
        text name
        int sortOrder
        text gitWorktreePath
        text createdAt
        text repoId FK
    }

    imported_issues {
        text linearId PK
        text identifier
        text title
        text status
        text statusId
        text url
        text labels "JSON array"
        int sortOrder
    }

    worktree_queue_items {
        text id PK
        text worktreeId FK
        text issueLinearId FK
        text queuePosition "inbox|processing|outbox"
        int sortOrder
        text assignedAt
        text completedAt
    }
```

Both foreign keys on `worktree_queue_items` use `ON DELETE CASCADE`, so deleting a worktree or an imported issue automatically cleans up its queue rows. The `MeisterFeature.onAppear` query uses a `NOT IN` subquery against `worktree_queue_items` to hide issues that are currently owned by any worktree queue.

## Terminal Layer

The terminal stack bypasses SwiftUI entirely once mounted — SwiftUI is only the outer shell.

```mermaid
flowchart LR
    NSEvent[NSEvent<br/>keystroke] --> SV[SurfaceView<br/>NSView + CAMetalLayer]
    SV --> KM[KeyMapping<br/>NSEvent → ghostty structs]
    KM --> GS[ghostty_surface_key]
    SV --> IKE[interpretKeyEvents]
    IKE --> NSTIC[NSTextInputClient<br/>IME composition]
    NSTIC --> GS

    GA[GhosttyApp<br/>MainActor singleton] --> GAT[ghostty_app_t]
    SS[SurfaceStore<br/>UUID → SurfaceView] --> SV
    SMan[SurfaceManager] --> SS
    SMan --> GA

    AF[AppFeature] --> SMan
```

**Why a singleton for `GhosttyApp`?** libghostty's C API owns a global app handle (`ghostty_app_t`) with `void*` userdata pointers wired into runtime callbacks. Getting that userdata wrong compiles fine but crashes at runtime (see `CLAUDE.md` libghostty callback rules). The `GhosttyApp` `@MainActor` class is the single owner of that handle; all callers go through `GhosttyAppClient`.

**Why no sandbox?** PTY spawning requires subprocess creation, which the App Sandbox blocks. Hardened runtime is still enabled.

## Runtime Routing

`TerminalContainerView` is a three-way switch driven from `AppFeature.State`:

```mermaid
flowchart TD
    Start{AppFeature.State}
    Start -->|showMeister == true| MTV[MeisterTabView<br/>kanban + swimlanes]
    Start -->|selectedWorktreeId != nil| WDV[WorktreeDetailView<br/>single worktree]
    Start -->|default| TCO[TerminalContentView<br/>NSViewRepresentable → SurfaceView]

    MTV --> MF[MeisterFeature store]
    MTV --> WF[WorktreeFeature store]
    WDV --> WF
    TCO --> SM[SurfaceStore]
```

State invariants keep these mutually exclusive: `.meisterTapped` sets `showMeister = true` and clears `activeTabID`; `.tabSelected(id)` sets `showMeister = false`; selecting a worktree in the sidebar clears both.

## Directory Layout

```
Klausemeister/
├── KlausemeisterApp.swift         @main, window, keyboard commands
├── AppFeature.swift               Root reducer + routing state
├── TerminalContainerView.swift    Three-way detail pane router
├── Database/                      GRDB records + migrations
├── Dependencies/                  @Dependency clients
├── Linear/                        MeisterFeature + Linear models + auth
├── Terminal/                      SurfaceView, GhosttyApp, KeyMapping
├── Theme/                         Everforest palette + AppTheme
├── Views/                         Shared SwiftUI views
└── Worktrees/                     WorktreeFeature + swimlane views
```

## Key Conventions

- **State is `@ObservableState`** on every feature; views use `StoreOf<Feature>` or `@Bindable var store` (never `WithViewStore`).
- **Side effects live in `Effect.run`**; reducer bodies are synchronous state mutation only.
- **Presentation components** (`IssueCardView`, `SwimlaneRowView`) take plain values and closures — no store dependency — and are reused across contexts.
- **Delegate actions** (`.delegate(.event)`) are the only mechanism for cross-feature communication; the parent intercepts them in its `Reduce` block.
- **Dependency clients** are structs of closures, not protocols. Test values use `unimplemented(...)` to loudly fail on unstubbed paths.
- **libghostty** calls are verified against upstream headers via the `context7` MCP — see `CLAUDE.md` for the verification rules.
