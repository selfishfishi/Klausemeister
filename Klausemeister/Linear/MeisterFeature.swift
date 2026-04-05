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
                    await send(.workflowStatesLoaded(
                        TaskResult { try await linearAPIClient.fetchWorkflowStates() }
                    ))
                    let records = try await databaseClient.fetchImportedIssues()
                    await send(.issuesLoadedFromDB(records))
                }

            case .importSubmitted:
                let text = state.importText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return .none }
                let identifier = MeisterFeature.extractIdentifier(from: text)
                state.isImporting = true
                state.importText = ""
                return .run { send in
                    await send(.issueImported(
                        TaskResult { try await linearAPIClient.fetchIssue(identifier) }
                    ))
                }

            case let .issueImported(.success(issue)):
                state.isImporting = false
                // Avoid duplicates
                let alreadyExists = state.columns.contains { column in
                    column.issues.contains { $0.id == issue.id }
                }
                guard !alreadyExists else { return .none }
                // Add to correct column by statusId
                if state.columns[id: issue.statusId] != nil {
                    state.columns[id: issue.statusId]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                let record = ImportedIssueRecord(from: issue)
                return .run { _ in
                    try await databaseClient.saveImportedIssue(record)
                }

            case let .issueImported(.failure(error)):
                state.isImporting = false
                state.error = String(describing: error)
                return .none

            case .refreshAllIssues:
                state.isRefreshing = true
                let allIssueIds = state.columns.flatMap { $0.issues.map(\.identifier) }
                return .run { send in
                    var refreshed: [LinearIssue] = []
                    for identifier in allIssueIds {
                        if let issue = try? await linearAPIClient.fetchIssue(identifier) {
                            refreshed.append(issue)
                        }
                    }
                    await send(.issuesRefreshed(.success(refreshed)))
                }

            case let .issuesRefreshed(.success(issues)):
                state.isRefreshing = false
                // Clear all columns
                for index in state.columns.indices {
                    state.columns[index].issues = []
                }
                // Re-distribute issues to columns
                for issue in issues {
                    if state.columns[id: issue.statusId] != nil {
                        state.columns[id: issue.statusId]?.issues.append(issue)
                    }
                }
                return .run { _ in
                    for issue in issues {
                        try await databaseClient.updateIssueFromLinear(ImportedIssueRecord(from: issue))
                    }
                }

            case .issuesRefreshed(.failure):
                state.isRefreshing = false
                return .none

            case let .workflowStatesLoaded(.success(states)):
                state.workflowStates = states
                let existingIssues = Dictionary(
                    grouping: state.columns.flatMap(\.issues),
                    by: \.statusId
                )
                state.columns = IdentifiedArrayOf(uniqueElements: states.map { ws in
                    KanbanColumn(
                        id: ws.id,
                        name: ws.name,
                        type: ws.type,
                        issues: existingIssues[ws.id] ?? []
                    )
                })
                return .none

            case .workflowStatesLoaded(.failure):
                return .none

            case let .issuesLoadedFromDB(records):
                for record in records {
                    let issue = LinearIssue(from: record)
                    if state.columns[id: issue.statusId] != nil {
                        let alreadyExists = state.columns[id: issue.statusId]!.issues.contains {
                            $0.id == issue.id
                        }
                        if !alreadyExists {
                            state.columns[id: issue.statusId]?.issues.append(issue)
                        }
                    }
                }
                return .none

            case let .issueMoved(issueId, fromColumnId, toColumnId):
                guard let sourceColumn = state.columns[id: fromColumnId],
                      let issueIndex = sourceColumn.issues.firstIndex(where: { $0.id == issueId }),
                      let targetColumn = state.columns[id: toColumnId]
                else { return .none }

                let originalIssue = sourceColumn.issues[issueIndex]

                // Create updated issue with new status from target column
                let movedIssue = LinearIssue(
                    id: originalIssue.id,
                    identifier: originalIssue.identifier,
                    title: originalIssue.title,
                    status: targetColumn.name,
                    statusId: targetColumn.id,
                    statusType: targetColumn.type,
                    projectName: originalIssue.projectName,
                    assigneeName: originalIssue.assigneeName,
                    priority: originalIssue.priority,
                    labels: originalIssue.labels,
                    description: originalIssue.description,
                    url: originalIssue.url,
                    createdAt: originalIssue.createdAt,
                    updatedAt: originalIssue.updatedAt
                )

                // Optimistic update
                state.columns[id: fromColumnId]?.issues.remove(at: issueIndex)
                state.columns[id: toColumnId]?.issues.append(movedIssue)

                return .run { send in
                    try await linearAPIClient.updateIssueStatus(issueId, toColumnId)
                    try await databaseClient.updateIssueStatus(
                        issueId, targetColumn.name, toColumnId, targetColumn.type
                    )
                    await send(.statusUpdateSucceeded(issueId: issueId))
                } catch: { error, send in
                    await send(.statusUpdateFailed(
                        issueId: issueId,
                        restoreToColumnId: fromColumnId,
                        originalIssue: originalIssue
                    ))
                }

            case let .moveToStatusTapped(issueId, statusId):
                // Find current column for the issue
                guard let currentColumn = state.columns.first(where: { column in
                    column.issues.contains { $0.id == issueId }
                }) else { return .none }
                return .send(.issueMoved(
                    issueId: issueId,
                    fromColumnId: currentColumn.id,
                    toColumnId: statusId
                ))

            case .statusUpdateSucceeded:
                return .none

            case let .statusUpdateFailed(issueId, restoreToColumnId, originalIssue):
                // Remove from all columns
                for index in state.columns.indices {
                    state.columns[index].issues.removeAll { $0.id == issueId }
                }
                // Restore to original column
                state.columns[id: restoreToColumnId]?.issues.append(originalIssue)
                state.error = String(describing: LinearAPIError.issueNotFound(issueId))
                return .none

            case let .removeIssueTapped(issueId):
                for index in state.columns.indices {
                    state.columns[index].issues.removeAll { $0.id == issueId }
                }
                return .run { _ in
                    try await databaseClient.deleteImportedIssue(issueId)
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated static func extractIdentifier(from text: String) -> String {
        // Handle URLs like https://linear.app/<team>/issue/<IDENTIFIER>/<slug>
        if let url = URL(string: text),
           let host = url.host,
           host.contains("linear.app") {
            let components = url.pathComponents
            if let issueIndex = components.firstIndex(of: "issue"),
               issueIndex + 1 < components.count {
                return components[issueIndex + 1]
            }
        }
        return text
    }
}

// MARK: - Conversion Extensions

extension LinearIssue {
    init(from record: ImportedIssueRecord) {
        let decodedLabels: [String]
        if let data = record.labels.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            decodedLabels = parsed
        } else {
            decodedLabels = []
        }
        self.init(
            id: record.linearId,
            identifier: record.identifier,
            title: record.title,
            status: record.status,
            statusId: record.statusId,
            statusType: record.statusType,
            projectName: record.projectName,
            assigneeName: record.assigneeName,
            priority: record.priority,
            labels: decodedLabels,
            description: record.description,
            url: record.url,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}

extension ImportedIssueRecord {
    init(from issue: LinearIssue) {
        let labelsJSON: String
        if let data = try? JSONEncoder().encode(issue.labels),
           let str = String(data: data, encoding: .utf8) {
            labelsJSON = str
        } else {
            labelsJSON = "[]"
        }
        self.init(
            linearId: issue.id,
            identifier: issue.identifier,
            title: issue.title,
            status: issue.status,
            statusId: issue.statusId,
            statusType: issue.statusType,
            projectName: issue.projectName,
            assigneeName: issue.assigneeName,
            priority: issue.priority,
            labels: labelsJSON,
            description: issue.description,
            url: issue.url,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            importedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0
        )
    }
}
