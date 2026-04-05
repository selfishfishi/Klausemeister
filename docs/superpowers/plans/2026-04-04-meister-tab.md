# KLA-12 + KLA-30: Meister Tab & GRDB Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a kanban board tab for managing imported Linear issues, backed by GRDB persistence with immediate status sync to Linear.

**Architecture:** GRDB database layer (DatabaseClient TCA dependency) → extended LinearAPIClient with issue fetch/update mutations → MeisterFeature TCA reducer for kanban state → SwiftUI kanban board views → sidebar integration with detail area switching in AppFeature.

**Tech Stack:** Swift, TCA 1.25, GRDB, SwiftUI (drag-and-drop, context menus), Linear GraphQL API

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Klausemeister/Database/DatabaseClient.swift` | Create | TCA dependency wrapping DatabaseQueue |
| `Klausemeister/Database/DatabaseMigrations.swift` | Create | Versioned migration: imported_issues table |
| `Klausemeister/Database/ImportedIssueRecord.swift` | Create | GRDB Record for imported_issues |
| `Klausemeister/Linear/LinearModels.swift` | Modify | Add LinearIssue, LinearWorkflowState |
| `Klausemeister/Linear/LinearConfig.swift` | Modify | Scope → "read,write" |
| `Klausemeister/Dependencies/LinearAPIClient.swift` | Modify | Add fetchIssue, updateIssueStatus, fetchWorkflowStates |
| `Klausemeister/Linear/MeisterFeature.swift` | Create | Kanban reducer |
| `Klausemeister/Views/MeisterView.swift` | Create | Import bar + horizontal kanban |
| `Klausemeister/Views/KanbanColumnView.swift` | Create | Single status column with drop target |
| `Klausemeister/Views/IssueCardView.swift` | Create | Draggable card with context menu |
| `Klausemeister/Views/SidebarView.swift` | Modify | Add Meister item at top |
| `Klausemeister/AppFeature.swift` | Modify | Add showMeister, meister scope |
| `Klausemeister/TerminalContainerView.swift` | Modify | Switch detail area |
| `Klausemeister/KlausemeisterApp.swift` | Modify | Wire DatabaseClient |
| `Klausemeister.xcodeproj/project.pbxproj` | Modify | Add GRDB SPM |
| `KlausemeisterTests/MeisterFeatureTests.swift` | Create | Reducer tests |

---

### Task 1: GRDB SPM dependency, DatabaseClient, migrations, record type

**Files:**
- Modify: `Klausemeister.xcodeproj/project.pbxproj`
- Create: `Klausemeister/Database/DatabaseClient.swift`
- Create: `Klausemeister/Database/DatabaseMigrations.swift`
- Create: `Klausemeister/Database/ImportedIssueRecord.swift`

- [ ] **Step 1: Add GRDB SPM to project.pbxproj**

Add to `/* Begin XCRemoteSwiftPackageReference section */`:

```
A8GR00002F816B35005797B3 /* XCRemoteSwiftPackageReference "GRDB.swift" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/groue/GRDB.swift.git";
    requirement = {
        kind = upToNextMajorVersion;
        minimumVersion = 7.0.0;
    };
};
```

Add to `/* Begin XCSwiftPackageProductDependency section */`:

```
A8GR00012F816B35005797B3 /* GRDB */ = {
    isa = XCSwiftPackageProductDependency;
    package = A8GR00002F816B35005797B3 /* XCRemoteSwiftPackageReference "GRDB.swift" */;
    productName = GRDB;
};
```

Add to `/* Begin PBXBuildFile section */`:

```
A8GR00022F816B35005797B3 /* GRDB in Frameworks */ = {isa = PBXBuildFile; productRef = A8GR00012F816B35005797B3 /* GRDB */; };
```

Add `A8GR00022F816B35005797B3 /* GRDB in Frameworks */,` to the app target's Frameworks build phase files list.

Add `A8GR00012F816B35005797B3 /* GRDB */,` to the app target's `packageProductDependencies`.

Add `A8GR00002F816B35005797B3 /* XCRemoteSwiftPackageReference "GRDB.swift" */,` to the project's `packageReferences`.

- [ ] **Step 2: Create Database directory**

```bash
mkdir -p Klausemeister/Database
```

- [ ] **Step 3: Create ImportedIssueRecord**

```swift
// Klausemeister/Database/ImportedIssueRecord.swift
import Foundation
import GRDB

struct ImportedIssueRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "imported_issues"

    var linearId: String
    var identifier: String
    var title: String
    var status: String
    var statusId: String
    var statusType: String
    var projectName: String?
    var assigneeName: String?
    var priority: Int
    var labels: String // JSON array of label names
    var description: String?
    var url: String
    var createdAt: String
    var updatedAt: String
    var importedAt: String
    var sortOrder: Int
}
```

- [ ] **Step 4: Create DatabaseMigrations**

```swift
// Klausemeister/Database/DatabaseMigrations.swift
import Foundation
import GRDB

enum DatabaseMigrations {
    nonisolated static func registerAll(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-imported-issues") { db in
            try db.create(table: "imported_issues") { t in
                t.column("linearId", .text).primaryKey()
                t.column("identifier", .text).notNull()
                t.column("title", .text).notNull()
                t.column("status", .text).notNull()
                t.column("statusId", .text).notNull()
                t.column("statusType", .text).notNull()
                t.column("projectName", .text)
                t.column("assigneeName", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("labels", .text).notNull().defaults(to: "[]")
                t.column("description", .text)
                t.column("url", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
                t.column("importedAt", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }
    }
}
```

- [ ] **Step 5: Create DatabaseClient**

```swift
// Klausemeister/Database/DatabaseClient.swift
import Dependencies
import Foundation
import GRDB

struct DatabaseClient: Sendable {
    var fetchImportedIssues: @Sendable () async throws -> [ImportedIssueRecord]
    var saveImportedIssue: @Sendable (ImportedIssueRecord) async throws -> Void
    var deleteImportedIssue: @Sendable (_ linearId: String) async throws -> Void
    var updateIssueStatus: @Sendable (
        _ linearId: String, _ status: String, _ statusId: String, _ statusType: String
    ) async throws -> Void
    var updateIssueFromLinear: @Sendable (ImportedIssueRecord) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    nonisolated static let liveValue: DatabaseClient = {
        let dbQueue: DatabaseQueue = {
            do {
                let fileManager = FileManager.default
                let appSupport = fileManager.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first!
                let appDir = appSupport.appendingPathComponent("Klausemeister")
                try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

                let dbQueue = try DatabaseQueue(
                    path: appDir.appendingPathComponent("klausemeister.db").path
                )
                var migrator = DatabaseMigrator()
                DatabaseMigrations.registerAll(&migrator)
                try migrator.migrate(dbQueue)
                return dbQueue
            } catch {
                fatalError("Failed to initialize database: \(error)")
            }
        }()

        return DatabaseClient(
            fetchImportedIssues: {
                try await dbQueue.read { db in
                    try ImportedIssueRecord
                        .order(Column("sortOrder").asc)
                        .fetchAll(db)
                }
            },
            saveImportedIssue: { record in
                try await dbQueue.write { db in
                    try record.save(db)
                }
            },
            deleteImportedIssue: { linearId in
                try await dbQueue.write { db in
                    _ = try ImportedIssueRecord.deleteOne(db, key: linearId)
                }
            },
            updateIssueStatus: { linearId, status, statusId, statusType in
                try await dbQueue.write { db in
                    if var record = try ImportedIssueRecord.fetchOne(db, key: linearId) {
                        record.status = status
                        record.statusId = statusId
                        record.statusType = statusType
                        try record.update(db)
                    }
                }
            },
            updateIssueFromLinear: { record in
                try await dbQueue.write { db in
                    try record.save(db)
                }
            }
        )
    }()

    nonisolated static let testValue = DatabaseClient(
        fetchImportedIssues: unimplemented("DatabaseClient.fetchImportedIssues"),
        saveImportedIssue: unimplemented("DatabaseClient.saveImportedIssue"),
        deleteImportedIssue: unimplemented("DatabaseClient.deleteImportedIssue"),
        updateIssueStatus: unimplemented("DatabaseClient.updateIssueStatus"),
        updateIssueFromLinear: unimplemented("DatabaseClient.updateIssueFromLinear")
    )
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}
```

- [ ] **Step 6: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (after resolving GRDB package).

- [ ] **Step 7: Commit**

```bash
git add Klausemeister.xcodeproj/ Klausemeister/Database/
git commit -m "Add GRDB persistence layer with DatabaseClient and imported_issues migration"
```

---

### Task 2: LinearIssue, LinearWorkflowState models + scope change

**Files:**
- Modify: `Klausemeister/Linear/LinearModels.swift`
- Modify: `Klausemeister/Linear/LinearConfig.swift`

- [ ] **Step 1: Add new model types to LinearModels.swift**

Append to the end of `Klausemeister/Linear/LinearModels.swift`:

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

struct LinearWorkflowState: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let position: Double
}
```

- [ ] **Step 2: Update OAuth scope**

In `Klausemeister/Linear/LinearConfig.swift`, change:

```swift
nonisolated static let scopes = "read"
```

to:

```swift
nonisolated static let scopes = "read,write"
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Linear/LinearModels.swift Klausemeister/Linear/LinearConfig.swift
git commit -m "Add LinearIssue, LinearWorkflowState models and upgrade OAuth scope to read,write"
```

---

### Task 3: LinearAPIClient extensions

**Files:**
- Modify: `Klausemeister/Dependencies/LinearAPIClient.swift`

- [ ] **Step 1: Add three new endpoints to LinearAPIClient**

Read `Klausemeister/Dependencies/LinearAPIClient.swift` first. Add three new closure properties to the struct and implement their live/test values.

The struct becomes:

```swift
struct LinearAPIClient: Sendable {
    var me: @Sendable () async throws -> LinearUser
    var fetchIssue: @Sendable (_ identifier: String) async throws -> LinearIssue
    var updateIssueStatus: @Sendable (_ issueId: String, _ statusId: String) async throws -> Void
    var fetchWorkflowStates: @Sendable () async throws -> [LinearWorkflowState]
}
```

In the `liveValue`, add these implementations:

**fetchIssue** — GraphQL query by identifier:

```swift
fetchIssue: { identifier in
    guard let tokenData = try await keychainClient.load(
        LinearConfig.keychainService,
        LinearConfig.accessTokenAccount
    ), let token = String(data: tokenData, encoding: .utf8) else {
        throw OAuthError.unauthorized
    }

    let query = """
    query($filter: IssueFilter!) {
      issues(filter: $filter, first: 1) {
        nodes {
          id identifier title url description priority createdAt updatedAt
          state { id name type position }
          project { name }
          assignee { name }
          labels { nodes { name } }
        }
      }
    }
    """
    let variables: [String: Any] = [
        "filter": ["identifier": ["eq": identifier]]
    ]

    let responseData = try await graphQLRequest(token: token, query: query, variables: variables)

    struct Response: Decodable {
        struct Data: Decodable {
            struct Issues: Decodable {
                struct Node: Decodable {
                    let id: String
                    let identifier: String
                    let title: String
                    let url: String
                    let description: String?
                    let priority: Int
                    let createdAt: String
                    let updatedAt: String
                    struct State: Decodable { let id: String; let name: String; let type: String }
                    let state: State
                    struct Project: Decodable { let name: String }
                    let project: Project?
                    struct Assignee: Decodable { let name: String }
                    let assignee: Assignee?
                    struct Labels: Decodable { struct Node: Decodable { let name: String }; let nodes: [Node] }
                    let labels: Labels
                }
                let nodes: [Node]
            }
            let issues: Issues
        }
        let data: Data
    }
    let resp = try JSONDecoder().decode(Response.self, from: responseData)
    guard let node = resp.data.issues.nodes.first else {
        throw OAuthError.networkError
    }
    return LinearIssue(
        id: node.id,
        identifier: node.identifier,
        title: node.title,
        status: node.state.name,
        statusId: node.state.id,
        statusType: node.state.type,
        projectName: node.project?.name,
        assigneeName: node.assignee?.name,
        priority: node.priority,
        labels: node.labels.nodes.map(\.name),
        description: node.description,
        url: node.url,
        createdAt: node.createdAt,
        updatedAt: node.updatedAt
    )
}
```

**updateIssueStatus** — GraphQL mutation:

```swift
updateIssueStatus: { issueId, statusId in
    guard let tokenData = try await keychainClient.load(
        LinearConfig.keychainService,
        LinearConfig.accessTokenAccount
    ), let token = String(data: tokenData, encoding: .utf8) else {
        throw OAuthError.unauthorized
    }

    let query = """
    mutation($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) { success }
    }
    """
    let variables: [String: Any] = [
        "id": issueId,
        "input": ["stateId": statusId]
    ]
    _ = try await graphQLRequest(token: token, query: query, variables: variables)
}
```

**fetchWorkflowStates** — fetches the viewer's first team's states:

```swift
fetchWorkflowStates: {
    guard let tokenData = try await keychainClient.load(
        LinearConfig.keychainService,
        LinearConfig.accessTokenAccount
    ), let token = String(data: tokenData, encoding: .utf8) else {
        throw OAuthError.unauthorized
    }

    let query = """
    query {
      organization {
        teams(first: 1) {
          nodes {
            states {
              nodes { id name type position }
            }
          }
        }
      }
    }
    """
    let responseData = try await graphQLRequest(token: token, query: query, variables: nil)

    struct Response: Decodable {
        struct Data: Decodable {
            struct Org: Decodable {
                struct Teams: Decodable {
                    struct Team: Decodable {
                        struct States: Decodable {
                            struct Node: Decodable {
                                let id: String; let name: String; let type: String; let position: Double
                            }
                            let nodes: [Node]
                        }
                        let states: States
                    }
                    let nodes: [Team]
                }
                let teams: Teams
            }
            let organization: Org
        }
        let data: Data
    }
    let resp = try JSONDecoder().decode(Response.self, from: responseData)
    guard let team = resp.data.organization.teams.nodes.first else { return [] }
    return team.states.nodes
        .map { LinearWorkflowState(id: $0.id, name: $0.name, type: $0.type, position: $0.position) }
        .sorted { $0.position < $1.position }
}
```

**Extract shared GraphQL helper** at file scope:

```swift
private nonisolated func graphQLRequest(
    token: String, query: String, variables: [String: Any]?
) async throws -> Data {
    var request = URLRequest(url: LinearConfig.graphqlURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = ["query": query]
    if let variables { body["variables"] = variables }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw OAuthError.networkError
    }
    if httpResponse.statusCode == 401 { throw OAuthError.unauthorized }
    return data
}
```

Update `testValue` to include the new endpoints:

```swift
nonisolated static let testValue = LinearAPIClient(
    me: unimplemented("LinearAPIClient.me"),
    fetchIssue: unimplemented("LinearAPIClient.fetchIssue"),
    updateIssueStatus: unimplemented("LinearAPIClient.updateIssueStatus"),
    fetchWorkflowStates: unimplemented("LinearAPIClient.fetchWorkflowStates")
)
```

Also refactor the existing `me` endpoint to use the shared `graphQLRequest` helper.

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Step 3: Run existing tests** (ensure nothing broke)

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" 2>&1 | grep -E "Test case|SUCCEEDED|FAILED"
```

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Dependencies/LinearAPIClient.swift
git commit -m "Extend LinearAPIClient with fetchIssue, updateIssueStatus, fetchWorkflowStates"
```

---

### Task 4: MeisterFeature reducer (TDD)

**Files:**
- Create: `Klausemeister/Linear/MeisterFeature.swift`
- Create: `KlausemeisterTests/MeisterFeatureTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// KlausemeisterTests/MeisterFeatureTests.swift
import ComposableArchitecture
import Testing
@testable import Klausemeister

@Test func importIssueSuccess() async {
    let testIssue = LinearIssue(
        id: "issue-1", identifier: "KLA-12", title: "Create Meister tab",
        status: "In Progress", statusId: "state-3", statusType: "started",
        projectName: "MVP", assigneeName: "Ali", priority: 2,
        labels: ["feature"], description: "Build the kanban board",
        url: "https://linear.app/test/issue/KLA-12", createdAt: "2026-04-04", updatedAt: "2026-04-04"
    )
    let states = [
        LinearWorkflowState(id: "state-1", name: "Backlog", type: "backlog", position: 0),
        LinearWorkflowState(id: "state-2", name: "Todo", type: "unstarted", position: 1),
        LinearWorkflowState(id: "state-3", name: "In Progress", type: "started", position: 2),
        LinearWorkflowState(id: "state-4", name: "Done", type: "completed", position: 3),
    ]

    var initialState = MeisterFeature.State()
    initialState.columns = IdentifiedArray(uniqueElements: states.map {
        MeisterFeature.KanbanColumn(id: $0.id, name: $0.name, type: $0.type)
    })
    initialState.workflowStates = states
    initialState.importText = "KLA-12"

    let store = TestStore(initialState: initialState) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchIssue = { _ in testIssue }
        $0.databaseClient.saveImportedIssue = { _ in }
    }

    await store.send(.importSubmitted) {
        $0.isImporting = true
        $0.importText = ""
    }
    await store.receive(\.issueImported.success) {
        $0.isImporting = false
        $0.columns[id: "state-3"]?.issues = [testIssue]
    }
}

@Test func importIssueFromURL() async {
    let testIssue = LinearIssue(
        id: "issue-1", identifier: "KLA-15", title: "Linear API integration",
        status: "Done", statusId: "state-4", statusType: "completed",
        projectName: "MVP", assigneeName: nil, priority: 3,
        labels: [], description: nil,
        url: "https://linear.app/test/issue/KLA-15", createdAt: "2026-04-04", updatedAt: "2026-04-04"
    )
    let states = [
        LinearWorkflowState(id: "state-4", name: "Done", type: "completed", position: 3),
    ]

    var initialState = MeisterFeature.State()
    initialState.columns = IdentifiedArray(uniqueElements: states.map {
        MeisterFeature.KanbanColumn(id: $0.id, name: $0.name, type: $0.type)
    })
    initialState.workflowStates = states
    initialState.importText = "https://linear.app/selfishfish/issue/KLA-15/linear-api-integration"

    let store = TestStore(initialState: initialState) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchIssue = { identifier in
            #expect(identifier == "KLA-15")
            return testIssue
        }
        $0.databaseClient.saveImportedIssue = { _ in }
    }

    await store.send(.importSubmitted) {
        $0.isImporting = true
        $0.importText = ""
    }
    await store.receive(\.issueImported.success) {
        $0.isImporting = false
        $0.columns[id: "state-4"]?.issues = [testIssue]
    }
}

@Test func moveIssueOptimisticSuccess() async {
    let issue = LinearIssue(
        id: "issue-1", identifier: "KLA-12", title: "Create Meister tab",
        status: "Todo", statusId: "state-2", statusType: "unstarted",
        projectName: "MVP", assigneeName: nil, priority: 2,
        labels: [], description: nil,
        url: "https://linear.app/test/issue/KLA-12", createdAt: "2026-04-04", updatedAt: "2026-04-04"
    )
    let states = [
        LinearWorkflowState(id: "state-2", name: "Todo", type: "unstarted", position: 1),
        LinearWorkflowState(id: "state-3", name: "In Progress", type: "started", position: 2),
    ]

    var initialState = MeisterFeature.State()
    initialState.workflowStates = states
    initialState.columns = IdentifiedArray(uniqueElements: [
        MeisterFeature.KanbanColumn(id: "state-2", name: "Todo", type: "unstarted", issues: [issue]),
        MeisterFeature.KanbanColumn(id: "state-3", name: "In Progress", type: "started"),
    ])

    let store = TestStore(initialState: initialState) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.updateIssueStatus = { _, _ in }
        $0.databaseClient.updateIssueStatus = { _, _, _, _ in }
    }

    await store.send(.issueMoved(issueId: "issue-1", fromColumnId: "state-2", toColumnId: "state-3")) {
        $0.columns[id: "state-2"]?.issues = []
        var movedIssue = issue
        movedIssue = LinearIssue(
            id: issue.id, identifier: issue.identifier, title: issue.title,
            status: "In Progress", statusId: "state-3", statusType: "started",
            projectName: issue.projectName, assigneeName: issue.assigneeName,
            priority: issue.priority, labels: issue.labels, description: issue.description,
            url: issue.url, createdAt: issue.createdAt, updatedAt: issue.updatedAt
        )
        $0.columns[id: "state-3"]?.issues = [movedIssue]
    }
    await store.receive(\.statusUpdateSucceeded)
}

@Test func moveIssueRollbackOnFailure() async {
    let issue = LinearIssue(
        id: "issue-1", identifier: "KLA-12", title: "Create Meister tab",
        status: "Todo", statusId: "state-2", statusType: "unstarted",
        projectName: nil, assigneeName: nil, priority: 0,
        labels: [], description: nil,
        url: "https://linear.app/test/issue/KLA-12", createdAt: "2026-04-04", updatedAt: "2026-04-04"
    )

    var initialState = MeisterFeature.State()
    initialState.workflowStates = [
        LinearWorkflowState(id: "state-2", name: "Todo", type: "unstarted", position: 1),
        LinearWorkflowState(id: "state-3", name: "In Progress", type: "started", position: 2),
    ]
    initialState.columns = IdentifiedArray(uniqueElements: [
        MeisterFeature.KanbanColumn(id: "state-2", name: "Todo", type: "unstarted", issues: [issue]),
        MeisterFeature.KanbanColumn(id: "state-3", name: "In Progress", type: "started"),
    ])

    let store = TestStore(initialState: initialState) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.updateIssueStatus = { _, _ in throw OAuthError.networkError }
        $0.databaseClient.updateIssueStatus = { _, _, _, _ in }
    }

    await store.send(.issueMoved(issueId: "issue-1", fromColumnId: "state-2", toColumnId: "state-3")) {
        $0.columns[id: "state-2"]?.issues = []
        var movedIssue = issue
        movedIssue = LinearIssue(
            id: issue.id, identifier: issue.identifier, title: issue.title,
            status: "In Progress", statusId: "state-3", statusType: "started",
            projectName: issue.projectName, assigneeName: issue.assigneeName,
            priority: issue.priority, labels: issue.labels, description: issue.description,
            url: issue.url, createdAt: issue.createdAt, updatedAt: issue.updatedAt
        )
        $0.columns[id: "state-3"]?.issues = [movedIssue]
    }
    await store.receive(\.statusUpdateFailed) {
        // Rolled back
        $0.columns[id: "state-3"]?.issues = []
        $0.columns[id: "state-2"]?.issues = [issue]
        $0.error = "networkError"
    }
}

@Test func removeIssue() async {
    let issue = LinearIssue(
        id: "issue-1", identifier: "KLA-12", title: "Create Meister tab",
        status: "Todo", statusId: "state-2", statusType: "unstarted",
        projectName: nil, assigneeName: nil, priority: 0,
        labels: [], description: nil,
        url: "https://linear.app/test/issue/KLA-12", createdAt: "2026-04-04", updatedAt: "2026-04-04"
    )

    var initialState = MeisterFeature.State()
    initialState.columns = IdentifiedArray(uniqueElements: [
        MeisterFeature.KanbanColumn(id: "state-2", name: "Todo", type: "unstarted", issues: [issue]),
    ])

    let store = TestStore(initialState: initialState) {
        MeisterFeature()
    } withDependencies: {
        $0.databaseClient.deleteImportedIssue = { _ in }
    }

    await store.send(.removeIssueTapped(issueId: "issue-1")) {
        $0.columns[id: "state-2"]?.issues = []
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" -only-testing:KlausemeisterTests/MeisterFeatureTests 2>&1 | tail -10
```

Expected: FAIL — `MeisterFeature` not found.

- [ ] **Step 3: Implement MeisterFeature**

```swift
// Klausemeister/Linear/MeisterFeature.swift
import ComposableArchitecture
import Foundation

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

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case importSubmitted
        case issueImported(TaskResult<LinearIssue>)
        case refreshAllIssues
        case issuesRefreshed(TaskResult<[LinearIssue]>)
        case workflowStatesLoaded(TaskResult<[LinearWorkflowState]>)
        case issuesLoadedFromDB([ImportedIssueRecord])
        case issueMoved(issueId: String, fromColumnId: String, toColumnId: String)
        case moveToStatusTapped(issueId: String, statusId: String)
        case statusUpdateSucceeded(issueId: String)
        case statusUpdateFailed(issueId: String, restoreToColumnId: String, originalIssue: LinearIssue)
        case removeIssueTapped(issueId: String)
    }

    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    // Load workflow states from Linear
                    await send(.workflowStatesLoaded(
                        TaskResult { try await linearAPIClient.fetchWorkflowStates() }
                    ))
                    // Load saved issues from DB
                    let records = (try? await databaseClient.fetchImportedIssues()) ?? []
                    await send(.issuesLoadedFromDB(records))
                    // Refresh from Linear
                    await send(.refreshAllIssues)
                }

            case let .workflowStatesLoaded(.success(states)):
                state.workflowStates = states
                state.columns = IdentifiedArray(uniqueElements: states.map {
                    KanbanColumn(id: $0.id, name: $0.name, type: $0.type)
                })
                return .none

            case .workflowStatesLoaded(.failure):
                state.error = "Failed to load workflow states"
                return .none

            case let .issuesLoadedFromDB(records):
                for record in records {
                    let issue = LinearIssue(from: record)
                    if state.columns[id: record.statusId] != nil {
                        state.columns[id: record.statusId]?.issues.append(issue)
                    }
                }
                return .none

            case .importSubmitted:
                let text = state.importText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return .none }
                state.isImporting = true
                state.importText = ""
                let identifier = Self.extractIdentifier(from: text)
                return .run { send in
                    await send(.issueImported(
                        TaskResult { try await linearAPIClient.fetchIssue(identifier) }
                    ))
                }

            case let .issueImported(.success(issue)):
                state.isImporting = false
                if state.columns[id: issue.statusId] != nil {
                    // Avoid duplicates
                    let alreadyExists = state.columns.flatMap(\.issues).contains { $0.id == issue.id }
                    if !alreadyExists {
                        state.columns[id: issue.statusId]?.issues.append(issue)
                    }
                }
                return .run { [issue] _ in
                    try await databaseClient.saveImportedIssue(ImportedIssueRecord(from: issue))
                }

            case let .issueImported(.failure(error)):
                state.isImporting = false
                state.error = String(describing: error)
                return .none

            case .refreshAllIssues:
                state.isRefreshing = true
                let issueIds = state.columns.flatMap(\.issues).map(\.identifier)
                return .run { send in
                    var refreshed: [LinearIssue] = []
                    for id in issueIds {
                        if let issue = try? await linearAPIClient.fetchIssue(id) {
                            refreshed.append(issue)
                        }
                    }
                    await send(.issuesRefreshed(.success(refreshed)))
                }

            case let .issuesRefreshed(.success(issues)):
                state.isRefreshing = false
                // Clear all columns and redistribute
                for index in state.columns.indices {
                    state.columns[index].issues = []
                }
                for issue in issues {
                    if state.columns[id: issue.statusId] != nil {
                        state.columns[id: issue.statusId]?.issues.append(issue)
                    }
                }
                return .run { [issues] _ in
                    for issue in issues {
                        try? await databaseClient.updateIssueFromLinear(ImportedIssueRecord(from: issue))
                    }
                }

            case .issuesRefreshed(.failure):
                state.isRefreshing = false
                return .none

            case let .issueMoved(issueId, fromColumnId, toColumnId):
                guard fromColumnId != toColumnId,
                      let issueIndex = state.columns[id: fromColumnId]?.issues.firstIndex(where: { $0.id == issueId }),
                      let targetColumn = state.columns[id: toColumnId],
                      let targetState = state.workflowStates.first(where: { $0.id == toColumnId })
                else { return .none }

                let originalIssue = state.columns[id: fromColumnId]!.issues[issueIndex]
                // Optimistic: move immediately
                state.columns[id: fromColumnId]?.issues.remove(at: issueIndex)
                let updatedIssue = LinearIssue(
                    id: originalIssue.id, identifier: originalIssue.identifier, title: originalIssue.title,
                    status: targetColumn.name, statusId: toColumnId, statusType: targetColumn.type,
                    projectName: originalIssue.projectName, assigneeName: originalIssue.assigneeName,
                    priority: originalIssue.priority, labels: originalIssue.labels,
                    description: originalIssue.description, url: originalIssue.url,
                    createdAt: originalIssue.createdAt, updatedAt: originalIssue.updatedAt
                )
                state.columns[id: toColumnId]?.issues.append(updatedIssue)

                return .run { send in
                    do {
                        try await linearAPIClient.updateIssueStatus(issueId, targetState.id)
                        try await databaseClient.updateIssueStatus(
                            issueId, targetColumn.name, toColumnId, targetColumn.type
                        )
                        await send(.statusUpdateSucceeded(issueId: issueId))
                    } catch {
                        await send(.statusUpdateFailed(
                            issueId: issueId,
                            restoreToColumnId: fromColumnId,
                            originalIssue: originalIssue
                        ))
                    }
                }

            case let .moveToStatusTapped(issueId, statusId):
                // Find current column
                guard let fromColumn = state.columns.first(where: { $0.issues.contains { $0.id == issueId } })
                else { return .none }
                return .send(.issueMoved(issueId: issueId, fromColumnId: fromColumn.id, toColumnId: statusId))

            case .statusUpdateSucceeded:
                return .none

            case let .statusUpdateFailed(issueId, restoreToColumnId, originalIssue):
                // Rollback: remove from current column, restore to original
                for index in state.columns.indices {
                    state.columns[index].issues.removeAll { $0.id == issueId }
                }
                state.columns[id: restoreToColumnId]?.issues.append(originalIssue)
                state.error = String(describing: OAuthError.networkError)
                return .none

            case let .removeIssueTapped(issueId):
                for index in state.columns.indices {
                    state.columns[index].issues.removeAll { $0.id == issueId }
                }
                return .run { _ in
                    try? await databaseClient.deleteImportedIssue(issueId)
                }
            }
        }
    }

    // MARK: - Helpers

    static func extractIdentifier(from text: String) -> String {
        // Handle full URLs: https://linear.app/<team>/issue/<IDENTIFIER>/<slug>
        if text.contains("linear.app"), let url = URL(string: text) {
            let components = url.pathComponents
            if let issueIndex = components.firstIndex(of: "issue"),
               issueIndex + 1 < components.count {
                return components[issueIndex + 1]
            }
        }
        return text
    }
}

// MARK: - Record Conversions

extension LinearIssue {
    init(from record: ImportedIssueRecord) {
        self.init(
            id: record.linearId, identifier: record.identifier, title: record.title,
            status: record.status, statusId: record.statusId, statusType: record.statusType,
            projectName: record.projectName, assigneeName: record.assigneeName,
            priority: record.priority,
            labels: (try? JSONDecoder().decode([String].self, from: Data(record.labels.utf8))) ?? [],
            description: record.description, url: record.url,
            createdAt: record.createdAt, updatedAt: record.updatedAt
        )
    }
}

extension ImportedIssueRecord {
    init(from issue: LinearIssue) {
        let labelsJSON = (try? String(data: JSONEncoder().encode(issue.labels), encoding: .utf8)) ?? "[]"
        self.init(
            linearId: issue.id, identifier: issue.identifier, title: issue.title,
            status: issue.status, statusId: issue.statusId, statusType: issue.statusType,
            projectName: issue.projectName, assigneeName: issue.assigneeName,
            priority: issue.priority, labels: labelsJSON,
            description: issue.description, url: issue.url,
            createdAt: issue.createdAt, updatedAt: issue.updatedAt,
            importedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0
        )
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" -only-testing:KlausemeisterTests/MeisterFeatureTests 2>&1 | tail -15
```

Expected: All 5 tests PASS.

**Troubleshooting:** If `IdentifiedArray` operations fail, ensure `KanbanColumn` conforms to `Identifiable` with `id: String`. If `TaskResult` matching fails, adjust `store.receive` patterns. The test assertions for `issueMoved` must reconstruct the full `LinearIssue` with updated status fields since `LinearIssue` uses `let` properties.

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/Linear/MeisterFeature.swift KlausemeisterTests/MeisterFeatureTests.swift
git commit -m "Add MeisterFeature kanban reducer with full TDD test coverage"
```

---

### Task 5: IssueCardView and KanbanColumnView

**Files:**
- Create: `Klausemeister/Views/IssueCardView.swift`
- Create: `Klausemeister/Views/KanbanColumnView.swift`

- [ ] **Step 1: Create IssueCardView**

```swift
// Klausemeister/Views/IssueCardView.swift
import SwiftUI

struct IssueCardView: View {
    let issue: LinearIssue
    let workflowStates: [LinearWorkflowState]
    let onMoveToStatus: (_ issueId: String, _ statusId: String) -> Void
    let onRemove: (_ issueId: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(issue.title)
                .font(.callout)
                .lineLimit(2)
            if let projectName = issue.projectName {
                Text(projectName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .draggable(issue.id)
        .contextMenu {
            Menu("Move to...") {
                ForEach(workflowStates.filter { $0.id != issue.statusId }) { state in
                    Button(state.name) {
                        onMoveToStatus(issue.id, state.id)
                    }
                }
            }
            Divider()
            Button("Remove from board", role: .destructive) {
                onRemove(issue.id)
            }
        }
    }
}
```

- [ ] **Step 2: Create KanbanColumnView**

```swift
// Klausemeister/Views/KanbanColumnView.swift
import SwiftUI

struct KanbanColumnView: View {
    let column: MeisterFeature.KanbanColumn
    let workflowStates: [LinearWorkflowState]
    let onMoveToStatus: (_ issueId: String, _ statusId: String) -> Void
    let onRemove: (_ issueId: String) -> Void
    let onDrop: (_ issueId: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(column.name.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(column.issues.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Cards
            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(column.issues, id: \.id) { issue in
                        IssueCardView(
                            issue: issue,
                            workflowStates: workflowStates,
                            onMoveToStatus: onMoveToStatus,
                            onRemove: onRemove
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 200, idealWidth: 240)
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            guard let issueId = items.first else { return false }
            onDrop(issueId)
            return true
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Views/IssueCardView.swift Klausemeister/Views/KanbanColumnView.swift
git commit -m "Add IssueCardView and KanbanColumnView with drag-drop and context menus"
```

---

### Task 6: MeisterView

**Files:**
- Create: `Klausemeister/Views/MeisterView.swift`

- [ ] **Step 1: Create MeisterView**

```swift
// Klausemeister/Views/MeisterView.swift
import ComposableArchitecture
import SwiftUI

struct MeisterView: View {
    @Bindable var store: StoreOf<MeisterFeature>

    var body: some View {
        VStack(spacing: 0) {
            // Import bar
            HStack(spacing: 8) {
                TextField("Import issue: KLA-15 or paste URL...", text: $store.importText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.send(.importSubmitted) }

                if store.isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            // Error banner
            if let error = store.error {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        store.send(.set(\.error, nil))
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Kanban board
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.columns) { column in
                        KanbanColumnView(
                            column: column,
                            workflowStates: store.workflowStates,
                            onMoveToStatus: { issueId, statusId in
                                store.send(.moveToStatusTapped(issueId: issueId, statusId: statusId))
                            },
                            onRemove: { issueId in
                                store.send(.removeIssueTapped(issueId: issueId))
                            },
                            onDrop: { issueId in
                                guard let fromColumn = store.columns.first(where: {
                                    $0.issues.contains { $0.id == issueId }
                                }) else { return }
                                store.send(.issueMoved(
                                    issueId: issueId,
                                    fromColumnId: fromColumn.id,
                                    toColumnId: column.id
                                ))
                            }
                        )
                    }
                }
                .padding(12)
            }

            if store.isRefreshing {
                ProgressView("Refreshing...")
                    .controlSize(.small)
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { store.send(.onAppear) }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Views/MeisterView.swift
git commit -m "Add MeisterView with import bar and horizontal kanban board"
```

---

### Task 7: Sidebar integration, AppFeature wiring, build verification

**Files:**
- Modify: `Klausemeister/AppFeature.swift`
- Modify: `Klausemeister/Views/SidebarView.swift`
- Modify: `Klausemeister/TerminalContainerView.swift`

- [ ] **Step 1: Add Meister state and actions to AppFeature**

Read `Klausemeister/AppFeature.swift`. Add:

To `State`:
```swift
var showMeister: Bool = false
var meister = MeisterFeature.State()
```

To `Action`:
```swift
case meisterTapped
case meister(MeisterFeature.Action)
```

Add `Scope` in `body` — before the existing `Reduce`:
```swift
Scope(state: \.meister, action: \.meister) {
    MeisterFeature()
}
```

Add handler cases in the switch:
```swift
case .meisterTapped:
    state.showMeister = true
    state.activeTabID = nil
    return .none

case .meister:
    return .none
```

Modify `.tabSelected` to clear `showMeister`:
```swift
case let .tabSelected(id):
    guard state.tabs[id: id] != nil,
          id != state.activeTabID else { return .none }
    state.showMeister = false  // <-- add this line
    let oldID = state.activeTabID
    state.activeTabID = id
    // ... rest unchanged
```

- [ ] **Step 2: Add Meister item to SidebarView**

Read `Klausemeister/Views/SidebarView.swift`. Add a Meister button above the tab list, inside the `List` but before `ForEach(store.tabs)`:

```swift
// Meister item at top of sidebar
Button {
    store.send(.meisterTapped)
} label: {
    HStack(spacing: 6) {
        Image(systemName: "squares.leading.rectangle")
            .foregroundStyle(.secondary)
        Text("Meister")
            .lineLimit(1)
        Spacer()
    }
}
.buttonStyle(.plain)
.padding(.vertical, 4)
.background(
    store.showMeister
        ? RoundedRectangle(cornerRadius: 6).fill(.selection).opacity(0.5)
        : nil
)
.listRowSeparator(.hidden)

Section("Terminals") {
    ForEach(store.tabs) { tab in
        // ... existing tab rows
    }
}
```

Adjust the `List` selection binding to clear when Meister is shown, and set selection to `nil` when `showMeister` is true.

- [ ] **Step 3: Switch detail area in TerminalContainerView**

Read `Klausemeister/TerminalContainerView.swift`. Replace the `detail:` content:

```swift
} detail: {
    if store.showMeister {
        MeisterView(store: store.scope(state: \.meister, action: \.meister))
    } else {
        TerminalContentView(
            surfaceView: store.activeTabID.flatMap { surfaceStore.surface(for: $0) },
            activeTabID: store.activeTabID
        )
        .ignoresSafeArea(edges: [.bottom, .horizontal])
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
    }
}
```

- [ ] **Step 4: Run full build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
```

- [ ] **Step 5: Run all tests**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="-" 2>&1 | grep -E "Test case|SUCCEEDED|FAILED"
```

Expected: All tests pass (existing + 5 new Meister tests).

- [ ] **Step 6: Commit**

```bash
git add Klausemeister/AppFeature.swift Klausemeister/Views/SidebarView.swift Klausemeister/TerminalContainerView.swift
git commit -m "Wire Meister tab into sidebar and AppFeature with detail area switching"
```

- [ ] **Step 7: Fix any build warnings**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS,arch=arm64' 2>&1 | grep "warning:" | grep -v "appintentsmetadataprocessor"
```

Fix any warnings (likely `nonisolated` or `await` issues). Commit fixes if needed.
