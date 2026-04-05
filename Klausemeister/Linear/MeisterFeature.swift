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
        var error: String?
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
        case issueDropped(issueId: String, onColumnId: String)
        case issueMoved(issueId: String, fromColumnId: String, toColumnId: String)
        case moveToStatusTapped(issueId: String, statusId: String)
        case statusUpdateSucceeded(issueId: String)
        case statusUpdateFailed(issueId: String, restoreToColumnId: String, originalIssue: LinearIssue)
        case removeIssueTapped(issueId: String)
        case assignIssueToWorktree(issue: LinearIssue, worktreeId: String)
        case issueReturnedFromWorktree(issue: LinearIssue)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case issueAssignedToWorktree(issue: LinearIssue, worktreeId: String)
        }
    }

    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.date) var date

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    async let statesResult: [LinearWorkflowState] = linearAPIClient.fetchWorkflowStates()
                    async let recordsResult: [ImportedIssueRecord] = databaseClient.fetchImportedIssuesExcludingWorktreeQueues()
                    do {
                        let states = try await statesResult
                        await send(.workflowStatesLoaded(.success(states)))
                    } catch {
                        await send(.workflowStatesLoaded(.failure(error)))
                    }
                    let records = await (try? recordsResult) ?? []
                    await send(.issuesLoadedFromDB(records))
                }
                .cancellable(id: "MeisterFeature.load", cancelInFlight: true)

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
                let alreadyExists = state.columns.contains { $0.issues.contains { $0.id == issue.id } }
                guard !alreadyExists else { return .none }
                if state.columns[id: issue.statusId] != nil {
                    state.columns[id: issue.statusId]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                let record = ImportedIssueRecord(from: issue, importedAt: date.now)
                return .run { _ in
                    try await databaseClient.saveImportedIssue(record)
                }

            case let .issueImported(.failure(error)):
                state.isImporting = false
                state.error = String(describing: error)
                return .none

            case .refreshAllIssues:
                state.isRefreshing = true
                let allIdentifiers = state.columns.flatMap { $0.issues.map(\.identifier) }
                return .run { send in
                    await send(.issuesRefreshed(
                        TaskResult { try await linearAPIClient.fetchIssues(allIdentifiers) }
                    ))
                }
                .cancellable(id: "MeisterFeature.refresh", cancelInFlight: true)

            case let .issuesRefreshed(.success(issues)):
                state.isRefreshing = false
                for index in state.columns.indices {
                    state.columns[index].issues = []
                }
                for issue in issues where state.columns[id: issue.statusId] != nil {
                    state.columns[id: issue.statusId]?.issues.append(issue)
                }
                let now = date.now
                let records = issues.map { ImportedIssueRecord(from: $0, importedAt: now) }
                return .run { _ in
                    try await databaseClient.batchSaveImportedIssues(records)
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
                state.columns = IdentifiedArrayOf(uniqueElements: states.map { workflowState in
                    KanbanColumn(
                        id: workflowState.id,
                        name: workflowState.name,
                        type: workflowState.type,
                        issues: existingIssues[workflowState.id] ?? []
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
                let movedIssue = originalIssue.withUpdatedStatus(
                    status: targetColumn.name,
                    statusId: targetColumn.id,
                    statusType: targetColumn.type
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
                } catch: { _, send in
                    await send(.statusUpdateFailed(
                        issueId: issueId,
                        restoreToColumnId: fromColumnId,
                        originalIssue: originalIssue
                    ))
                }

            case let .issueDropped(issueId, onColumnId):
                guard let fromColumn = state.columnContainingIssue(issueId) else { return .none }
                return .send(.issueMoved(
                    issueId: issueId,
                    fromColumnId: fromColumn.id,
                    toColumnId: onColumnId
                ))

            case let .moveToStatusTapped(issueId, statusId):
                guard let fromColumn = state.columnContainingIssue(issueId) else { return .none }
                return .send(.issueMoved(
                    issueId: issueId,
                    fromColumnId: fromColumn.id,
                    toColumnId: statusId
                ))

            case .statusUpdateSucceeded:
                return .none

            case let .statusUpdateFailed(issueId, restoreToColumnId, originalIssue):
                state.removeIssueFromAllColumns(issueId)
                state.columns[id: restoreToColumnId]?.issues.append(originalIssue)
                state.error = String(describing: LinearAPIError.issueNotFound(issueId))
                return .none

            case let .removeIssueTapped(issueId):
                state.removeIssueFromAllColumns(issueId)
                return .run { _ in
                    try await databaseClient.deleteImportedIssue(issueId)
                }

            case let .assignIssueToWorktree(issue, worktreeId):
                state.removeIssueFromAllColumns(issue.id)
                return .send(.delegate(.issueAssignedToWorktree(issue: issue, worktreeId: worktreeId)))

            case let .issueReturnedFromWorktree(issue):
                guard !state.columns.isEmpty else { return .none }
                let alreadyPresent = state.columns.contains { $0.issues.contains { $0.id == issue.id } }
                guard !alreadyPresent else { return .none }
                if state.columns[id: issue.statusId] != nil {
                    state.columns[id: issue.statusId]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Helpers

    nonisolated static func extractIdentifier(from text: String) -> String {
        if let url = URL(string: text),
           let host = url.host,
           host.contains("linear.app")
        {
            let components = url.pathComponents
            if let issueIndex = components.firstIndex(of: "issue"),
               issueIndex + 1 < components.count
            {
                return components[issueIndex + 1]
            }
        }
        return text
    }
}

// MARK: - State Helpers

extension MeisterFeature.State {
    func columnContainingIssue(_ issueId: String) -> MeisterFeature.KanbanColumn? {
        columns.first { $0.issues.contains { $0.id == issueId } }
    }

    mutating func removeIssueFromAllColumns(_ issueId: String) {
        for index in columns.indices {
            columns[index].issues.removeAll { $0.id == issueId }
        }
    }
}

// MARK: - LinearIssue Helpers

extension LinearIssue {
    func withUpdatedStatus(status: String, statusId: String, statusType: String) -> LinearIssue {
        LinearIssue(
            id: id, identifier: identifier, title: title,
            status: status, statusId: statusId, statusType: statusType,
            projectName: projectName, assigneeName: assigneeName,
            priority: priority, labels: labels, description: description,
            url: url, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Record Conversions

extension LinearIssue {
    init(from record: ImportedIssueRecord) {
        let decodedLabels: [String] = if let data = record.labels.data(using: .utf8),
                                         let parsed = try? JSONDecoder().decode([String].self, from: data)
        {
            parsed
        } else {
            []
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
    init(from issue: LinearIssue, importedAt: Date = Date()) {
        let labelsJSON: String = if let data = try? JSONEncoder().encode(issue.labels),
                                    let str = String(data: data, encoding: .utf8)
        {
            str
        } else {
            "[]"
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
            importedAt: ISO8601DateFormatter().string(from: importedAt),
            sortOrder: 0
        )
    }
}
