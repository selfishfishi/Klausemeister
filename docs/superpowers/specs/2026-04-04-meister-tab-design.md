# KLA-12 + KLA-30: Meister Tab & GRDB Persistence — Design Spec

## Goal

Build the Meister tab — a kanban board for managing imported Linear issues. Includes GRDB persistence (KLA-30) as the storage foundation.

## Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Tab model | Fixed sidebar item (not a tab type) | Always one click away, no tab type complexity |
| Layout | Kanban board (horizontal columns) | Better spatial status tracking than a list |
| Persistence | GRDB (SQLite) | Structured queries, migrations, scales to future features |
| Cached fields | Standard (~12 fields) | Single query, useful for future detail pane |
| Status sync | Immediate to Linear (optimistic UI) | Spec requirement; `read,write` OAuth scope |
| Refresh | On appear via TCA effects | Always fresh when looking, no polling |

## Data Model & Persistence (GRDB)

### Setup

- Add `GRDB` SPM dependency
- Database file at `Application Support/Klausemeister/klausemeister.db`
- `DatabaseClient` TCA dependency wrapping `DatabaseQueue`
- `DatabaseMigrator` with versioned migrations from day one

### `imported_issues` table

| Column | Type | Notes |
|--------|------|-------|
| `linearId` | TEXT PK | Linear's issue UUID |
| `identifier` | TEXT | e.g. `KLA-15` |
| `title` | TEXT | |
| `status` | TEXT | Linear status name |
| `statusId` | TEXT | Linear status UUID (for mutations) |
| `statusType` | TEXT | `backlog`, `unstarted`, `started`, `completed`, `cancelled` |
| `projectName` | TEXT? | nullable |
| `assigneeName` | TEXT? | nullable |
| `priority` | INTEGER | 0=none, 1=urgent...4=low |
| `labels` | TEXT | JSON array of label names |
| `description` | TEXT? | nullable, markdown |
| `url` | TEXT | Linear web URL |
| `createdAt` | TEXT | ISO8601 |
| `updatedAt` | TEXT | ISO8601 |
| `importedAt` | TEXT | When user imported it |
| `sortOrder` | INTEGER | Per-column ordering for kanban |

### TCA Integration

`DatabaseClient` dependency exposes:

```swift
struct DatabaseClient: Sendable {
    var fetchImportedIssues: @Sendable () async throws -> [ImportedIssueRecord]
    var saveImportedIssue: @Sendable (ImportedIssueRecord) async throws -> Void
    var deleteImportedIssue: @Sendable (_ linearId: String) async throws -> Void
    var updateIssueStatus: @Sendable (_ linearId: String, _ status: String, _ statusId: String, _ statusType: String) async throws -> Void
}
```

## LinearAPIClient Extensions

### New endpoints

```swift
// Added to LinearAPIClient:
var fetchIssue: @Sendable (_ idOrIdentifier: String) async throws -> LinearIssue
var updateIssueStatus: @Sendable (_ issueId: String, _ statusId: String) async throws -> Void
var fetchWorkflowStates: @Sendable (_ teamId: String) async throws -> [LinearWorkflowState]
```

- `fetchIssue` — GraphQL query by identifier (e.g. `KLA-15`) or URL-extracted slug. Returns full issue with all standard fields.
- `updateIssueStatus` — GraphQL mutation `issueUpdate(id:, stateId:)`. Requires `read,write` OAuth scope.
- `fetchWorkflowStates` — Fetches the team's workflow states with IDs, names, types, and positions.

### New model types

```swift
struct LinearIssue: Equatable, Sendable, Codable {
    let id: String
    let identifier: String
    let title: String
    let status: String
    let statusId: String
    let statusType: String
    let projectName: String?
    let assigneeName: String?
    let priority: Int
    let labels: [String]
    let description: String?
    let url: String
    let createdAt: String
    let updatedAt: String
}

struct LinearWorkflowState: Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let position: Double
}
```

### OAuth scope change

Update `LinearConfig.scopes` from `"read"` to `"read,write"`.

## MeisterFeature Reducer

### State

```swift
@Reducer
struct MeisterFeature {
    @ObservableState
    struct State: Equatable {
        var columns: IdentifiedArrayOf<KanbanColumn> = []
        var workflowStates: [LinearWorkflowState] = []
        var importText: String = ""
        var isImporting: Bool = false
        var isRefreshing: Bool = false
        var error: String? = nil
    }

    struct KanbanColumn: Equatable, Identifiable {
        let id: String
        let name: String
        let type: String
        var issues: [LinearIssue] = []
    }
}
```

### Actions

```swift
enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case onAppear
    case onDisappear
    case importSubmitted
    case issueImported(TaskResult<LinearIssue>)
    case refreshAllIssues
    case issuesRefreshed(TaskResult<[LinearIssue]>)
    case workflowStatesLoaded(TaskResult<[LinearWorkflowState]>)
    case issueMoved(issueId: String, toColumnId: String)
    case statusUpdateCompleted(issueId: String, TaskResult<VoidSuccess>)
    case moveToStatusTapped(issueId: String, statusId: String)
    case removeIssueTapped(issueId: String)
}
```

### Key flows

1. **`onAppear`** — Load workflow states from Linear, load imported issues from GRDB, then refresh all from Linear in background.
2. **`importSubmitted`** — Parse import text (URL or identifier), call `linearAPIClient.fetchIssue`, save to GRDB, add to correct column.
3. **`issueMoved` / `moveToStatusTapped`** — Optimistic UI: move the card immediately in state, then fire `linearAPIClient.updateIssueStatus`. On failure, roll back and show error.
4. **`refreshAllIssues`** — Re-fetch all imported issues from Linear, update GRDB and state.
5. **`removeIssueTapped`** — Delete from GRDB and remove from state. Does not change anything in Linear.

### Dependencies

```swift
@Dependency(\.linearAPIClient) var linearAPIClient
@Dependency(\.databaseClient) var databaseClient
```

## Sidebar Integration

The Meister gets a fixed item at the top of the sidebar, above terminal tabs.

### AppFeature additions

```swift
// State:
var showMeister: Bool = false
var meister = MeisterFeature.State()

// Action:
case meisterTapped
case meister(MeisterFeature.Action)
```

When `meisterTapped` fires: `showMeister = true`, `activeTabID = nil`. When a terminal tab is selected: `showMeister = false`. The detail area switches based on `showMeister`.

### Composition

```swift
// AppFeature body:
Scope(state: \.meister, action: \.meister) { MeisterFeature() }
```

## View Layer

### Detail area switching

```swift
// In TerminalContainerView detail:
if store.showMeister {
    MeisterView(store: store.scope(state: \.meister, action: \.meister))
} else {
    TerminalContentView(...)
}
```

### MeisterView structure

```
MeisterView
├── Import bar (text field + submit)
└── ScrollView(.horizontal)
    └── HStack(spacing:)
        ├── KanbanColumnView (per workflow state)
        └── ...

KanbanColumnView
├── Column header (status name + count)
└── ScrollView(.vertical)
    └── LazyVStack
        └── IssueCardView (per issue)
```

### IssueCardView

- Identifier label (e.g. `KLA-15`)
- Title
- Project badge
- `.draggable(issue.id)` for drag-and-drop
- `.contextMenu` with "Move to..." submenu and "Remove from board"

### KanbanColumnView

- `.dropDestination(for: String.self)` fires `issueMoved(issueId:toColumnId:)`

## File Layout

```
Klausemeister/
├── Database/
│   ├── DatabaseClient.swift
│   ├── DatabaseMigrations.swift
│   └── ImportedIssueRecord.swift
├── Linear/
│   ├── LinearConfig.swift            # scope → "read,write"
│   ├── LinearModels.swift            # + LinearIssue, LinearWorkflowState
│   ├── LinearAuthFeature.swift       # unchanged
│   └── MeisterFeature.swift
├── Dependencies/
│   ├── LinearAPIClient.swift         # + fetchIssue, updateIssueStatus, fetchWorkflowStates
│   ├── KeychainClient.swift          # unchanged
│   └── OAuthClient.swift             # unchanged
├── Views/
│   ├── SidebarView.swift             # + Meister item at top
│   ├── MeisterView.swift
│   ├── KanbanColumnView.swift
│   └── IssueCardView.swift
├── AppFeature.swift                  # + showMeister, meister scope
└── KlausemeisterApp.swift            # + DatabaseClient wiring
```

**New SPM dependency:** GRDB

## Verification

The Meister tab is working when:
1. User can import an issue by identifier or URL
2. Issue appears in the correct kanban column
3. Dragging a card to another column updates Linear's status
4. Right-click "Move to..." works identically
5. Imported issues persist across app restarts (GRDB)
6. Switching to Meister tab refreshes all issues from Linear
