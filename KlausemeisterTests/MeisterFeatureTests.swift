import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing
@testable import Klausemeister

// MARK: - Test Helpers

private let todoColumn = MeisterFeature.KanbanColumn(id: .todo)
private let inProgressColumn = MeisterFeature.KanbanColumn(id: .inProgress)
private let doneColumn = MeisterFeature.KanbanColumn(id: .completed)

private let sampleIssue = LinearIssue(
    id: "issue-1",
    identifier: "KLA-12",
    title: "Meister tab",
    status: "Todo",
    statusId: "state-todo",
    statusType: "unstarted",
    teamId: "team-1",
    projectName: "Klausemeister",
    labels: ["feature", "klause"],
    description: "Build the meister tab",
    url: "https://linear.app/selfishfish/issue/KLA-12/meister-tab",
    updatedAt: "2026-04-04",
    isOrphaned: false
)

private let sampleIssueKLA15 = LinearIssue(
    id: "issue-2",
    identifier: "KLA-15",
    title: "Linear API integration",
    status: "In Progress",
    statusId: "state-progress",
    statusType: "started",
    teamId: "team-1",
    projectName: "Klausemeister",
    labels: ["api", "klause"],
    description: nil,
    url: "https://linear.app/selfishfish/issue/KLA-15/linear-api-integration",
    updatedAt: "2026-04-04",
    isOrphaned: false
)

private let sampleWorkflowStates: WorkflowStatesByTeam = [
    "team-1": [
        LinearWorkflowState(id: "state-todo", name: "Todo", type: "unstarted", position: 1, teamId: "team-1"),
        LinearWorkflowState(id: "state-progress", name: "In Progress", type: "started", position: 2, teamId: "team-1"),
        LinearWorkflowState(id: "state-done", name: "Done", type: "completed", position: 3, teamId: "team-1")
    ]
]

// MARK: - Sync Tests

@Test func `sync populates columns by status type`() async {
    let testClock = TestClock()
    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { label, _ in
            #expect(label == MeisterFeature.syncLabel)
            return [sampleIssue, sampleIssueKLA15]
        }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchUnqueuedImportedIssues = { [] }
        $0.databaseClient.fetchWorkflowStates = { [] }
        $0.databaseClient.saveWorkflowStates = { _ in }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.databaseClient.markOrphanedIssues = { _, _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.continuousClock = testClock
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }
    await store.receive(\.delegate.syncStarted)

    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.workflowStatesLastFetched = Date(timeIntervalSince1970: 0)
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue, sampleIssueKLA15])
        $0.syncStatus = .succeeded
    }
    await store.receive(\.delegate.syncSucceeded)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }
}

@Test func `sync marks issues no longer labeled as orphaned`() async {
    // DB has both issues; fetch returns only one → the other is orphaned.
    let orphanedRecord = ImportedIssueRecord(from: sampleIssueKLA15, importedAt: Date(timeIntervalSince1970: 0))
    let testClock = TestClock()

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { _, _ in [sampleIssue] }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchUnqueuedImportedIssues = { [orphanedRecord] }
        $0.databaseClient.fetchWorkflowStates = { [] }
        $0.databaseClient.saveWorkflowStates = { _ in }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.databaseClient.markOrphanedIssues = { _, _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.continuousClock = testClock
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }
    await store.receive(\.delegate.syncStarted)

    var orphanedIssue = sampleIssueKLA15
    orphanedIssue.isOrphaned = true

    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.workflowStatesLastFetched = Date(timeIntervalSince1970: 0)
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue, orphanedIssue])
        $0.syncStatus = .succeeded
    }
    await store.receive(\.delegate.syncSucceeded)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }
}

@Test func `sync failure emits delegate and resets syncStatus`() async {
    struct TestError: Error, Equatable {}

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { _, _ in throw TestError() }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { [:] }
        $0.databaseClient.fetchUnqueuedImportedIssues = { [] }
        $0.databaseClient.fetchWorkflowStates = { [] }
        $0.databaseClient.saveWorkflowStates = { _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }
    await store.receive(\.delegate.syncStarted)

    await store.receive(\.syncCompleted.failure) {
        $0.syncStatus = .idle
    }
    await store.receive(\.delegate.syncFailed)
}

// MARK: - Move-to-status Tests

@Test func `move issue resolves team-specific workflow state`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let movedIssue = sampleIssue.withUpdatedStatus(
        status: "In Progress",
        statusId: "state-progress",
        statusType: "started"
    )

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [todoWithIssue, inProgressColumn, doneColumn],
            workflowStatesByTeam: sampleWorkflowStates
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.updateIssueStatus = { issueId, stateId in
            #expect(issueId == "issue-1")
            #expect(stateId == "state-progress")
        }
        $0.databaseClient.updateIssueStatus = { _, _, _, _ in }
    }

    await store.send(.issueMoved(
        issueId: sampleIssue.id,
        source: .todo,
        target: .inProgress
    )) {
        $0.columns[id: .todo]?.issues = []
        $0.columns[id: .inProgress]?.issues = [movedIssue]
    }

    await store.receive(\.statusUpdateSucceeded)
}

@Test func `move issue rollback on failure`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let movedIssue = sampleIssue.withUpdatedStatus(
        status: "In Progress",
        statusId: "state-progress",
        statusType: "started"
    )

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [todoWithIssue, inProgressColumn, doneColumn],
            workflowStatesByTeam: sampleWorkflowStates
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.updateIssueStatus = { _, _ in
            throw LinearAPIError.issueNotFound("issue-1")
        }
    }

    await store.send(.issueMoved(
        issueId: sampleIssue.id,
        source: .todo,
        target: .inProgress
    )) {
        $0.columns[id: .todo]?.issues = []
        $0.columns[id: .inProgress]?.issues = [movedIssue]
    }

    await store.receive(\.statusUpdateFailed) {
        $0.columns[id: .inProgress]?.issues = []
        $0.columns[id: .todo]?.issues = [sampleIssue]
    }
    await store.receive(\.delegate.errorOccurred)
}

// MARK: - Filter Tests

@Test func `completed stage is hidden by default`() {
    let state = MeisterFeature.State()
    #expect(state.hiddenStages == [.completed])
}

@Test func `visibleColumns excludes hidden stages`() {
    var state = MeisterFeature.State()
    state.columns = MeisterFeature.rebuildColumns(from: [])
    // Default: completed hidden
    #expect(state.visibleColumns.count == 5)
    #expect(state.visibleColumns[id: .completed] == nil)
    #expect(state.visibleColumns[id: .backlog] != nil)
}

@Test func `toggling a visible stage hides it and toggling again reveals it`() async {
    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    }

    // .backlog starts visible → hide it
    await store.send(.stageVisibilityToggled(.backlog)) {
        $0.hiddenStages = [.completed, .backlog]
    }

    // Toggle .completed back on
    await store.send(.stageVisibilityToggled(.completed)) {
        $0.hiddenStages = [.backlog]
    }

    // Toggle .backlog back on → back to empty
    await store.send(.stageVisibilityToggled(.backlog)) {
        $0.hiddenStages = []
    }
}

// MARK: - Remove Tests

@Test func `remove issue`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [todoWithIssue, inProgressColumn]
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.databaseClient.deleteImportedIssue = { _ in }
    }

    await store.send(.removeIssueTapped(issueId: sampleIssue.id)) {
        $0.columns[id: .todo]?.issues = []
    }
}

// MARK: - Ingestion Strategy Tests

private let teamLabelFiltered = LinearTeam(
    id: "team-1", key: "KLA", name: "Klausemeister",
    colorIndex: 0, isEnabled: true, isHiddenFromBoard: false,
    ingestionStrategy: .labelFiltered
)

private let teamAllIssues = LinearTeam(
    id: "team-2", key: "MOB", name: "Mobile",
    colorIndex: 1, isEnabled: true, isHiddenFromBoard: false,
    ingestionStrategy: .allIssues
)

private let mobileIssue = LinearIssue(
    id: "issue-mob-1",
    identifier: "MOB-1",
    title: "Mobile issue",
    status: "Todo",
    statusId: "state-todo",
    statusType: "unstarted",
    teamId: "team-2",
    projectName: nil,
    labels: [],
    description: nil,
    url: "https://linear.app/selfishfish/issue/MOB-1",
    updatedAt: "2026-04-12",
    isOrphaned: false
)

@Test func `teamsConfirmed dispatches by ingestion strategy`() async {
    let testClock = TestClock()
    var fetchLabeledCalled = false
    var fetchAllCalled = false

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { label, teamId in
            #expect(label == MeisterFeature.syncLabel)
            #expect(teamId == "team-1")
            fetchLabeledCalled = true
            return [sampleIssue]
        }
        $0.linearAPIClient.fetchAllTeamIssues = { teamId in
            #expect(teamId == "team-2")
            fetchAllCalled = true
            return [mobileIssue]
        }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchUnqueuedImportedIssues = { [] }
        $0.databaseClient.saveWorkflowStates = { _ in }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.continuousClock = testClock
    }

    let teams = [teamLabelFiltered, teamAllIssues]
    await store.send(.teamsConfirmed(teams)) {
        $0.teams = teams
        $0.syncStatus = .syncing
    }
    await store.receive(\.delegate.syncStarted)

    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.workflowStatesLastFetched = Date(timeIntervalSince1970: 0)
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue, mobileIssue])
        $0.syncStatus = .succeeded
    }
    await store.receive(\.delegate.syncSucceeded)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }

    #expect(fetchLabeledCalled)
    #expect(fetchAllCalled)
}

@Test func `sync partial failure reports error for failed teams`() async {
    let testClock = TestClock()

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { _, _ in [sampleIssue] }
        $0.linearAPIClient.fetchAllTeamIssues = { _ in
            throw LinearAPIError.rateLimited
        }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchUnqueuedImportedIssues = { [] }
        $0.databaseClient.saveWorkflowStates = { _ in }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.continuousClock = testClock
    }

    let teams = [teamLabelFiltered, teamAllIssues]
    await store.send(.teamsConfirmed(teams)) {
        $0.teams = teams
        $0.syncStatus = .syncing
    }
    await store.receive(\.delegate.syncStarted)

    // Sync succeeds overall but team-2 failed
    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.workflowStatesLastFetched = Date(timeIntervalSince1970: 0)
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue])
        $0.syncStatus = .succeeded
    }
    await store.receive(\.delegate.syncSucceeded)
    await store.receive(\.delegate.errorOccurred)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }
}
