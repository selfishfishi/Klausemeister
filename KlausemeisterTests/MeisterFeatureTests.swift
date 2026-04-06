import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing
@testable import Klausemeister

// MARK: - Test Helpers

private let todoColumn = MeisterFeature.KanbanColumn(id: "unstarted", name: "To Do")
private let inProgressColumn = MeisterFeature.KanbanColumn(id: "started", name: "In Progress")
private let doneColumn = MeisterFeature.KanbanColumn(id: "completed", name: "Done")

private let sampleIssue = LinearIssue(
    id: "issue-1",
    identifier: "KLA-12",
    title: "Meister tab",
    status: "Todo",
    statusId: "state-todo",
    statusType: "unstarted",
    teamId: "team-1",
    teamName: "KLA",
    projectName: "Klausemeister",
    assigneeName: "Ali",
    priority: 1,
    labels: ["feature", "klause"],
    description: "Build the meister tab",
    url: "https://linear.app/selfishfish/issue/KLA-12/meister-tab",
    createdAt: "2026-04-01",
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
    teamName: "KLA",
    projectName: "Klausemeister",
    assigneeName: "Ali",
    priority: 2,
    labels: ["api", "klause"],
    description: nil,
    url: "https://linear.app/selfishfish/issue/KLA-15/linear-api-integration",
    createdAt: "2026-04-02",
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
    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { label in
            #expect(label == MeisterFeature.syncLabel)
            return [sampleIssue, sampleIssueKLA15]
        }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchImportedIssuesExcludingWorktreeQueues = { [] }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.databaseClient.markOrphanedIssues = { _, _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }

    let expectedResult = MeisterFeature.SyncResult(
        issues: [sampleIssue, sampleIssueKLA15],
        workflowStatesByTeam: sampleWorkflowStates,
        orphanedIds: [],
        restoredIds: []
    )

    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue, sampleIssueKLA15])
        $0.syncStatus = .succeeded
    }

    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }

    _ = expectedResult
}

@Test func `sync marks issues no longer labeled as orphaned`() async {
    // DB has both issues; fetch returns only one → the other is orphaned.
    let orphanedRecord = ImportedIssueRecord(from: sampleIssueKLA15, importedAt: Date(timeIntervalSince1970: 0))

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { _ in [sampleIssue] }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { sampleWorkflowStates }
        $0.databaseClient.fetchImportedIssuesExcludingWorktreeQueues = { [orphanedRecord] }
        $0.databaseClient.batchSaveImportedIssues = { _ in }
        $0.databaseClient.markOrphanedIssues = { _, _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }

    var orphanedIssue = sampleIssueKLA15
    orphanedIssue.isOrphaned = true

    await store.receive(\.syncCompleted.success) {
        $0.workflowStatesByTeam = sampleWorkflowStates
        $0.columns = MeisterFeature.rebuildColumns(from: [sampleIssue, orphanedIssue])
        $0.syncStatus = .succeeded
    }

    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }
}

@Test func `sync failure sets error status`() async {
    struct TestError: Error, Equatable {}

    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchLabeledIssues = { _ in throw TestError() }
        $0.linearAPIClient.fetchWorkflowStatesByTeam = { [:] }
        $0.databaseClient.fetchImportedIssuesExcludingWorktreeQueues = { [] }
    }

    await store.send(.onAppear) {
        $0.syncStatus = .syncing
    }

    await store.receive(\.syncCompleted.failure) { state in
        if case .failed = state.syncStatus {
            // OK — specific message depends on localizedDescription
        } else {
            Issue.record("Expected syncStatus to be .failed")
        }
    }
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
        fromColumnId: "unstarted",
        toColumnId: "started"
    )) {
        $0.columns[id: "unstarted"]?.issues = []
        $0.columns[id: "started"]?.issues = [movedIssue]
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
        fromColumnId: "unstarted",
        toColumnId: "started"
    )) {
        $0.columns[id: "unstarted"]?.issues = []
        $0.columns[id: "started"]?.issues = [movedIssue]
    }

    await store.receive(\.statusUpdateFailed) {
        $0.columns[id: "started"]?.issues = []
        $0.columns[id: "unstarted"]?.issues = [sampleIssue]
        $0.error = "Failed to update issue status"
    }
}

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
        $0.columns[id: "unstarted"]?.issues = []
    }
}
