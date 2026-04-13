// swiftlint:disable file_length
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

@Test func `toggling project filter hides and reveals project`() async {
    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    } withDependencies: {
        $0.databaseClient.setProjectHidden = { _, _ in }
    }

    // Hide "Klausemeister"
    await store.send(.projectFilterToggled(projectName: "Klausemeister")) {
        $0.hiddenProjectNames = ["Klausemeister"]
    }

    // Toggle again → visible
    await store.send(.projectFilterToggled(projectName: "Klausemeister")) {
        $0.hiddenProjectNames = []
    }
}

@Test func `visibleColumns excludes hidden projects`() {
    let issueWithProject = LinearIssue(
        id: "i1", identifier: "KLA-1", title: "Has project",
        status: "Todo", statusId: "s1", statusType: "unstarted",
        teamId: "t1", projectName: "Alpha", labels: [],
        description: nil, url: "", updatedAt: "", isOrphaned: false
    )
    let issueNoProject = LinearIssue(
        id: "i2", identifier: "KLA-2", title: "No project",
        status: "Todo", statusId: "s2", statusType: "unstarted",
        teamId: "t1", projectName: nil, labels: [],
        description: nil, url: "", updatedAt: "", isOrphaned: false
    )

    var state = MeisterFeature.State()
    state.columns = MeisterFeature.rebuildColumns(from: [issueWithProject, issueNoProject])

    // Both visible by default
    let todoColumn = state.visibleColumns[id: .todo]
    #expect(todoColumn?.issues.count == 2)

    // Hide "Alpha" → only no-project issue remains
    state.hiddenProjectNames = ["Alpha"]
    let filtered = state.visibleColumns[id: .todo]
    #expect(filtered?.issues.count == 1)
    #expect(filtered?.issues.first?.id == "i2")

    // Hide no-project issues too
    state.hiddenProjectNames = ["Alpha", LinearIssue.noProjectName]
    let allHidden = state.visibleColumns[id: .todo]
    #expect(allHidden?.issues.count == 0)
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
        $0.stateMappingClient.fetchAll = { [] }
        $0.stateMappingClient.seedMappings = { _ in }
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
    await store.receive(\.stateMappingsLoaded)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }

    #expect(fetchLabeledCalled)
    #expect(fetchAllCalled)
}

// MARK: - State Mapping Tests

@Test func `computeSeedRecords seeds new states and skips existing`() {
    let existing = [
        StateMappingRecord(
            teamId: "team-1", linearStateId: "state-todo",
            linearStateName: "Todo", meisterState: "todo"
        )
    ]
    let fresh: [LinearWorkflowState] = [
        LinearWorkflowState(id: "state-todo", name: "Todo", type: "unstarted", position: 1, teamId: "team-1"),
        LinearWorkflowState(id: "state-ip", name: "In Progress", type: "started", position: 2, teamId: "team-1"),
        LinearWorkflowState(id: "state-canceled", name: "Canceled", type: "canceled", position: 5, teamId: "team-1")
    ]

    let seeds = StateMappingClient.computeSeedRecords(
        freshStates: fresh, existingMappings: existing
    )

    // state-todo already exists → skipped
    // state-canceled has type "canceled" → defaultMapping returns nil → skipped
    // state-ip is new → seeded
    #expect(seeds.count == 1)
    #expect(seeds.first?.linearStateId == "state-ip")
    #expect(seeds.first?.meisterState == "inProgress")
}

@Test func `rebuildColumns uses mapping table over heuristic`() {
    let issue = LinearIssue(
        id: "issue-1", identifier: "KLA-1", title: "Test",
        status: "Spec", statusId: "state-spec", statusType: "started",
        teamId: "team-1", projectName: nil, labels: [],
        description: nil, url: "", updatedAt: "", isOrphaned: false
    )

    // Without mapping: "Spec" has type "started" → heuristic maps to .inProgress
    let withoutMapping = MeisterFeature.rebuildColumns(from: [issue])
    #expect(withoutMapping[id: .inProgress]?.issues.count == 1)
    #expect(withoutMapping[id: .inReview]?.issues.count == 0)

    // With mapping: "state-spec" explicitly mapped to .inReview
    let mappings: StateMappingTable = ["team-1": ["state-spec": .inReview]]
    let withMapping = MeisterFeature.rebuildColumns(from: [issue], mappings: mappings)
    #expect(withMapping[id: .inProgress]?.issues.count == 0)
    #expect(withMapping[id: .inReview]?.issues.count == 1)
}

@Test func `defaultMapping heuristic — name match beats type fallback`() {
    let testingState = LinearWorkflowState(
        id: "s1", name: "Testing", type: "started", position: 1, teamId: "t1"
    )
    // Name "Testing" matches .testing despite type "started" which would give .inProgress
    #expect(MeisterState.defaultMapping(for: testingState) == .testing)

    let canceledState = LinearWorkflowState(
        id: "s2", name: "Canceled", type: "canceled", position: 2, teamId: "t1"
    )
    #expect(MeisterState.defaultMapping(for: canceledState) == nil)
}

// MARK: - Ingestion Strategy + Partial Failure Tests

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
        $0.stateMappingClient.fetchAll = { [] }
        $0.stateMappingClient.seedMappings = { _ in }
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
    await store.receive(\.delegate.syncPartiallyFailed)
    await store.receive(\.stateMappingsLoaded)

    await testClock.advance(by: .seconds(2))
    await store.receive(\.syncIndicatorReset) {
        $0.syncStatus = .idle
    }
}
