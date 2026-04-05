import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing
@testable import Klausemeister

// MARK: - Test Helpers

private let todoColumn = MeisterFeature.KanbanColumn(
    id: "state-todo", name: "Todo", type: "unstarted"
)
private let inProgressColumn = MeisterFeature.KanbanColumn(
    id: "state-progress", name: "In Progress", type: "started"
)
private let doneColumn = MeisterFeature.KanbanColumn(
    id: "state-done", name: "Done", type: "completed"
)

private let sampleIssue = LinearIssue(
    id: "issue-1",
    identifier: "KLA-12",
    title: "Meister tab",
    status: "Todo",
    statusId: "state-todo",
    statusType: "unstarted",
    projectName: "Klausemeister",
    assigneeName: "Ali",
    priority: 1,
    labels: ["feature"],
    description: "Build the meister tab",
    url: "https://linear.app/selfishfish/issue/KLA-12/meister-tab",
    createdAt: "2026-04-01",
    updatedAt: "2026-04-04"
)

private let sampleIssueKLA15 = LinearIssue(
    id: "issue-2",
    identifier: "KLA-15",
    title: "Linear API integration",
    status: "In Progress",
    statusId: "state-progress",
    statusType: "started",
    projectName: "Klausemeister",
    assigneeName: "Ali",
    priority: 2,
    labels: ["api"],
    description: nil,
    url: "https://linear.app/selfishfish/issue/KLA-15/linear-api-integration",
    createdAt: "2026-04-02",
    updatedAt: "2026-04-04"
)

// MARK: - Tests

@Test func `import issue success`() async {
    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [
                .init(id: todoColumn.id, name: todoColumn.name, type: todoColumn.type),
                .init(id: inProgressColumn.id, name: inProgressColumn.name, type: inProgressColumn.type),
                .init(id: doneColumn.id, name: doneColumn.name, type: doneColumn.type)
            ],
            importText: "KLA-12"
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchIssue = { identifier in
            #expect(identifier == "KLA-12")
            return sampleIssue
        }
        $0.databaseClient.saveImportedIssue = { _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    }

    await store.send(.importSubmitted) {
        $0.isImporting = true
        $0.importText = ""
    }

    await store.receive(\.issueImported.success) {
        $0.isImporting = false
        $0.columns[id: "state-todo"]?.issues = [sampleIssue]
    }
}

@Test func `import issue from URL`() async {
    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [
                .init(id: todoColumn.id, name: todoColumn.name, type: todoColumn.type),
                .init(id: inProgressColumn.id, name: inProgressColumn.name, type: inProgressColumn.type),
                .init(id: doneColumn.id, name: doneColumn.name, type: doneColumn.type)
            ],
            importText: "https://linear.app/selfishfish/issue/KLA-15/linear-api-integration"
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchIssue = { identifier in
            #expect(identifier == "KLA-15")
            return sampleIssueKLA15
        }
        $0.databaseClient.saveImportedIssue = { _ in }
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    }

    await store.send(.importSubmitted) {
        $0.isImporting = true
        $0.importText = ""
    }

    await store.receive(\.issueImported.success) {
        $0.isImporting = false
        $0.columns[id: "state-progress"]?.issues = [sampleIssueKLA15]
    }
}

@Test func `move issue optimistic success`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let movedIssue = LinearIssue(
        id: sampleIssue.id,
        identifier: sampleIssue.identifier,
        title: sampleIssue.title,
        status: inProgressColumn.name,
        statusId: inProgressColumn.id,
        statusType: inProgressColumn.type,
        projectName: sampleIssue.projectName,
        assigneeName: sampleIssue.assigneeName,
        priority: sampleIssue.priority,
        labels: sampleIssue.labels,
        description: sampleIssue.description,
        url: sampleIssue.url,
        createdAt: sampleIssue.createdAt,
        updatedAt: sampleIssue.updatedAt
    )

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [
                todoWithIssue,
                .init(id: inProgressColumn.id, name: inProgressColumn.name, type: inProgressColumn.type),
                .init(id: doneColumn.id, name: doneColumn.name, type: doneColumn.type)
            ]
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.linearAPIClient.updateIssueStatus = { _, _ in }
        $0.databaseClient.updateIssueStatus = { _, _, _, _ in }
    }

    await store.send(.issueMoved(
        issueId: sampleIssue.id,
        fromColumnId: todoColumn.id,
        toColumnId: inProgressColumn.id
    )) {
        $0.columns[id: todoColumn.id]?.issues = []
        $0.columns[id: inProgressColumn.id]?.issues = [movedIssue]
    }

    await store.receive(\.statusUpdateSucceeded)
}

@Test func `move issue rollback on failure`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let movedIssue = LinearIssue(
        id: sampleIssue.id,
        identifier: sampleIssue.identifier,
        title: sampleIssue.title,
        status: inProgressColumn.name,
        statusId: inProgressColumn.id,
        statusType: inProgressColumn.type,
        projectName: sampleIssue.projectName,
        assigneeName: sampleIssue.assigneeName,
        priority: sampleIssue.priority,
        labels: sampleIssue.labels,
        description: sampleIssue.description,
        url: sampleIssue.url,
        createdAt: sampleIssue.createdAt,
        updatedAt: sampleIssue.updatedAt
    )

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [
                todoWithIssue,
                .init(id: inProgressColumn.id, name: inProgressColumn.name, type: inProgressColumn.type),
                .init(id: doneColumn.id, name: doneColumn.name, type: doneColumn.type)
            ]
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
        fromColumnId: todoColumn.id,
        toColumnId: inProgressColumn.id
    )) {
        $0.columns[id: todoColumn.id]?.issues = []
        $0.columns[id: inProgressColumn.id]?.issues = [movedIssue]
    }

    await store.receive(\.statusUpdateFailed) {
        $0.columns[id: inProgressColumn.id]?.issues = []
        $0.columns[id: todoColumn.id]?.issues = [sampleIssue]
        $0.error = "issueNotFound(\"issue-1\")"
    }
}

@Test func `remove issue`() async {
    var todoWithIssue = todoColumn
    todoWithIssue.issues = [sampleIssue]

    let store = TestStore(
        initialState: MeisterFeature.State(
            columns: [
                todoWithIssue,
                .init(id: inProgressColumn.id, name: inProgressColumn.name, type: inProgressColumn.type)
            ]
        )
    ) {
        MeisterFeature()
    } withDependencies: {
        $0.databaseClient.deleteImportedIssue = { _ in }
    }

    await store.send(.removeIssueTapped(issueId: sampleIssue.id)) {
        $0.columns[id: todoColumn.id]?.issues = []
    }
}
