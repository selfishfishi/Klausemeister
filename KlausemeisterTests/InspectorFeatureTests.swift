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
