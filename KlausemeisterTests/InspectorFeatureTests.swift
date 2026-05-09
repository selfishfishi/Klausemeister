import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

// MARK: - Fixtures

// swiftlint:disable force_unwrapping
private let sampleTicketURL = URL(string: "https://linear.app/team/issue/KLA-42/example")!
// swiftlint:enable force_unwrapping

private let sampleDetail = InspectorTicketDetail(
    id: "abc-123",
    identifier: "KLA-42",
    title: "Example ticket",
    descriptionMarkdown: "Body",
    url: sampleTicketURL,
    project: .init(id: "p1", name: "The Inspector"),
    status: .init(id: "s1", name: "In Progress", type: .started),
    attachedPRs: []
)

private let currentSessionIssue = LinearIssue(
    id: "current-issue",
    identifier: "KLA-99",
    title: "Current session ticket",
    status: "In Progress",
    statusId: "state-in-progress",
    statusType: "started",
    teamId: "team-1",
    projectName: "Klausemeister",
    labels: [],
    description: nil,
    url: "https://linear.app/team/issue/KLA-99/current-session-ticket",
    createdAt: "2026-05-01",
    updatedAt: "2026-05-02"
)

private let currentWorktree = Worktree(
    id: "worktree-1",
    name: "delta",
    gitWorktreePath: "/tmp/delta",
    repoId: "repo-1",
    repoName: "Klausemeister",
    currentBranch: "feature/current",
    meisterStatusText: nil,
    meisterActivityText: nil,
    recapText: nil,
    meisterActivityUpdatedAt: nil,
    gitStats: nil,
    inbox: [],
    processing: currentSessionIssue,
    outbox: [],
    sortOrder: 0,
    tmuxSessionStatus: .sessionExists,
    meisterStatus: .running,
    meisterSessionState: .working(tool: nil),
    agent: .codex
)

// MARK: - AppFeature inspector reducer

@Test func `inspectorSelectionRequested success path transitions loading then loaded`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { _ in sampleDetail }
    }
    store.exhaustivity = .off

    await store.send(.inspectorSelectionRequested(issueId: "abc-123")) {
        $0.showInspector = true
        $0.inspectorSelection = .ticket(id: "abc-123")
        $0.inspectorDetail = .loading
    }

    await store.receive(\.inspectorDetailFetched) {
        $0.inspectorDetail = .loaded(sampleDetail)
    }
}

@Test func `inspectorSelectionRequested failure maps LinearAPIError to typed error state`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { id in
            throw LinearAPIError.issueNotFound(id)
        }
    }
    store.exhaustivity = .off

    await store.send(.inspectorSelectionRequested(issueId: "missing"))
    await store.receive(\.inspectorDetailFetched) {
        $0.inspectorDetail = .error(.notFound(id: "missing"))
    }
}

@Test func `inspectorSelectionRequested failure maps rate-limit to typed error state`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { _ in throw LinearAPIError.rateLimited }
    }
    store.exhaustivity = .off

    await store.send(.inspectorSelectionRequested(issueId: "x"))
    await store.receive(\.inspectorDetailFetched) {
        $0.inspectorDetail = .error(.rateLimited)
    }
}

@Test func `toggleInspector flips the showInspector flag`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.toggleInspector) {
        $0.showInspector = true
    }
    await store.send(.toggleInspector) {
        $0.showInspector = false
    }
}

@Test func `toggleInspector opens current session ticket when worktree is selected`() async {
    var state = AppFeature.State()
    state.showMeister = false
    state.worktree.selectedWorktreeId = currentWorktree.id
    state.worktree.worktrees = [currentWorktree]

    let store = TestStore(initialState: state) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { id in
            #expect(id == currentSessionIssue.id)
            return sampleDetail
        }
    }
    store.exhaustivity = .off

    await store.send(.toggleInspector)
    await store.receive(\.inspectorSelectionRequested) {
        $0.showInspector = true
        $0.inspectorSelection = .ticket(id: currentSessionIssue.id)
        $0.inspectorDetail = .loading
    }
    await store.receive(\.inspectorDetailFetched) {
        $0.inspectorDetail = .loaded(sampleDetail)
    }
}

@Test func `toggleInspector clears stale content when no current session ticket exists`() async {
    var state = AppFeature.State()
    state.inspectorSelection = .ticket(id: "stale")
    state.inspectorDetail = .loaded(sampleDetail)

    let store = TestStore(initialState: state) {
        AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.toggleInspector) {
        $0.showInspector = true
        $0.inspectorSelection = nil
        $0.inspectorDetail = .empty
    }
}

@Test func `meister delegate inspectorSelectionRequested re-dispatches at root`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { _ in sampleDetail }
    }
    store.exhaustivity = .off

    await store.send(.meister(.delegate(.inspectorSelectionRequested(issueId: "abc-123"))))
    await store.receive(\.inspectorSelectionRequested) {
        $0.showInspector = true
        $0.inspectorSelection = .ticket(id: "abc-123")
        $0.inspectorDetail = .loading
    }
}

@Test func `worktree delegate inspectorSelectionRequested re-dispatches at root`() async {
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTicketDetail = { _ in sampleDetail }
    }
    store.exhaustivity = .off

    await store.send(.worktree(.delegate(.inspectorSelectionRequested(issueId: "abc-123"))))
    await store.receive(\.inspectorSelectionRequested) {
        $0.showInspector = true
        $0.inspectorSelection = .ticket(id: "abc-123")
        $0.inspectorDetail = .loading
    }
}

// MARK: - MeisterFeature kanbanCardTapped

@Test func `kanbanCardTapped emits delegate inspectorSelectionRequested`() async {
    let store = TestStore(initialState: MeisterFeature.State()) {
        MeisterFeature()
    }
    store.exhaustivity = .off

    await store.send(.kanbanCardTapped(issueId: "abc-123"))
    await store.receive(\.delegate.inspectorSelectionRequested)
}

// MARK: - WorktreeFeature queueRowTapped

@Test func `queueRowTapped emits delegate inspectorSelectionRequested`() async {
    let store = TestStore(initialState: WorktreeFeature.State()) {
        WorktreeFeature()
    }
    store.exhaustivity = .off

    await store.send(.queueRowTapped(issueId: "abc-123"))
    await store.receive(\.delegate.inspectorSelectionRequested)
}
