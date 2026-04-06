import ComposableArchitecture
import Foundation

@Reducer
// swiftlint:disable:next type_body_length
struct MeisterFeature {
    @ObservableState
    struct State: Equatable {
        var columns: IdentifiedArrayOf<KanbanColumn> = []
        var workflowStatesByTeam: WorkflowStatesByTeam = [:]
        var syncStatus: SyncStatus = .idle
        var error: String?
    }

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case succeeded
        case failed(String)
    }

    struct SyncResult: Equatable {
        let issues: [LinearIssue]
        let workflowStatesByTeam: WorkflowStatesByTeam
        let orphanedIds: Set<String>
        let restoredIds: Set<String>
    }

    struct KanbanColumn: Equatable, Identifiable {
        let id: String // statusType string
        let name: String
        var issues: [LinearIssue] = []

        nonisolated static func displayName(forType type: String) -> String {
            switch type {
            case "backlog": "Backlog"
            case "unstarted": "To Do"
            case "started": "In Progress"
            case "completed": "Done"
            case "canceled": "Canceled"
            default: "Unknown"
            }
        }
    }

    nonisolated static let orderedColumnTypes = ["backlog", "unstarted", "started", "completed", "canceled"]
    nonisolated static let unknownColumnId = "unknown"
    nonisolated static let syncLabel = "klause"

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case refreshTapped
        case syncCompleted(TaskResult<SyncResult>)
        case syncIndicatorReset
        case issueDropped(issueId: String, onColumnId: String)
        case issueMoved(issueId: String, fromColumnId: String, toColumnId: String)
        case moveToStatusTapped(issueId: String, targetStatusType: String)
        case statusUpdateSucceeded(issueId: String)
        case statusUpdateFailed(issueId: String, restoreToColumnId: String, originalIssue: LinearIssue)
        case removeIssueTapped(issueId: String)
        case assignIssueToWorktree(issue: LinearIssue, worktreeId: String)
        case issueReturnedFromWorktree(issue: LinearIssue)
        case removeIssueFromColumns(issueId: String)
        case issueDroppedFromWorktree(issueId: String, onColumnId: String)
        case issueDroppedFromWorktreeResolved(issue: LinearIssue, onColumnId: String)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case issueAssignedToWorktree(issue: LinearIssue, worktreeId: String)
            case issueReturnedFromWorktreeByDrop(issueId: String)
        }
    }

    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.date) var date

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear, .refreshTapped:
                state.syncStatus = .syncing
                return .merge(
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    .run { [linearAPIClient, databaseClient] send in
                        await send(.syncCompleted(TaskResult {
                            try await performSync(
                                linearAPIClient: linearAPIClient,
                                databaseClient: databaseClient
                            )
                        }))
                    }
                    .cancellable(id: "MeisterFeature.load", cancelInFlight: true)
                )

            case let .syncCompleted(.success(result)):
                state.workflowStatesByTeam = result.workflowStatesByTeam
                state.columns = MeisterFeature.rebuildColumns(from: result.issues)
                state.syncStatus = .succeeded
                state.error = nil
                let now = date.now
                let records = result.issues.map { ImportedIssueRecord(from: $0, importedAt: now) }
                return .merge(
                    .run { [databaseClient] send in
                        do {
                            try await databaseClient.batchSaveImportedIssues(records)
                        } catch {
                            await send(.set(\.error, "Failed to save sync results: \(error.localizedDescription)"))
                        }
                    },
                    .run { send in
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        await send(.syncIndicatorReset)
                    }
                    .cancellable(id: "MeisterFeature.syncIndicatorReset", cancelInFlight: true)
                )

            case let .syncCompleted(.failure(error)):
                state.syncStatus = .failed(error.localizedDescription)
                return .none

            case .syncIndicatorReset:
                if state.syncStatus == .succeeded {
                    state.syncStatus = .idle
                }
                return .none

            case let .issueMoved(issueId, fromColumnId, toColumnId):
                guard let sourceColumn = state.columns[id: fromColumnId],
                      let issueIndex = sourceColumn.issues.firstIndex(where: { $0.id == issueId }),
                      state.columns[id: toColumnId] != nil
                else { return .none }

                let originalIssue = sourceColumn.issues[issueIndex]
                // Resolve the team-specific workflow state for the target type
                guard let teamStates = state.workflowStatesByTeam[originalIssue.teamId],
                      let targetState = teamStates.first(where: { $0.type == toColumnId })
                else {
                    // No matching workflow state for this team — cannot move
                    return .none
                }

                let movedIssue = originalIssue.withUpdatedStatus(
                    status: targetState.name,
                    statusId: targetState.id,
                    statusType: toColumnId
                )

                // Optimistic update
                state.columns[id: fromColumnId]?.issues.remove(at: issueIndex)
                state.columns[id: toColumnId]?.issues.append(movedIssue)

                return .run { send in
                    try await linearAPIClient.updateIssueStatus(issueId, targetState.id)
                    try await databaseClient.updateIssueStatus(
                        issueId, targetState.name, targetState.id, toColumnId
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
                if let fromColumn = state.columnContainingIssue(issueId) {
                    return .send(.issueMoved(
                        issueId: issueId,
                        fromColumnId: fromColumn.id,
                        toColumnId: onColumnId
                    ))
                }
                // Issue not in any column — coming from a worktree
                return .send(.issueDroppedFromWorktree(issueId: issueId, onColumnId: onColumnId))

            case let .moveToStatusTapped(issueId, targetStatusType):
                guard let fromColumn = state.columnContainingIssue(issueId) else { return .none }
                return .send(.issueMoved(
                    issueId: issueId,
                    fromColumnId: fromColumn.id,
                    toColumnId: targetStatusType
                ))

            case .statusUpdateSucceeded:
                return .none

            case let .statusUpdateFailed(_, restoreToColumnId, originalIssue):
                state.removeIssueFromAllColumns(originalIssue.id)
                state.columns[id: restoreToColumnId]?.issues.append(originalIssue)
                state.error = "Failed to update issue status"
                return .none

            case let .removeIssueTapped(issueId):
                state.removeIssueFromAllColumns(issueId)
                return .run { _ in
                    try await databaseClient.deleteImportedIssue(issueId)
                }

            case let .removeIssueFromColumns(issueId):
                state.removeIssueFromAllColumns(issueId)
                return .none

            case let .assignIssueToWorktree(issue, worktreeId):
                state.removeIssueFromAllColumns(issue.id)
                return .send(.delegate(.issueAssignedToWorktree(issue: issue, worktreeId: worktreeId)))

            case let .issueReturnedFromWorktree(issue):
                guard !state.columns.isEmpty else { return .none }
                let alreadyPresent = state.columns.contains { $0.issues.contains { $0.id == issue.id } }
                guard !alreadyPresent else { return .none }
                let targetColumnId = MeisterFeature.columnId(forType: issue.statusType)
                if state.columns[id: targetColumnId] != nil {
                    state.columns[id: targetColumnId]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                return .none

            case let .issueDroppedFromWorktree(issueId, onColumnId):
                return .run { send in
                    guard let record = try await databaseClient.fetchImportedIssue(issueId) else { return }
                    let issue = LinearIssue(from: record)
                    await send(.issueDroppedFromWorktreeResolved(issue: issue, onColumnId: onColumnId))
                }

            case let .issueDroppedFromWorktreeResolved(issue, onColumnId):
                let alreadyPresent = state.columns.contains { $0.issues.contains { $0.id == issue.id } }
                guard !alreadyPresent else { return .none }
                if state.columns[id: onColumnId] != nil {
                    state.columns[id: onColumnId]?.issues.append(issue)
                } else {
                    let typeColumnId = MeisterFeature.columnId(forType: issue.statusType)
                    if state.columns[id: typeColumnId] != nil {
                        state.columns[id: typeColumnId]?.issues.append(issue)
                    } else if let firstColumn = state.columns.first {
                        state.columns[id: firstColumn.id]?.issues.append(issue)
                    }
                }
                return .send(.delegate(.issueReturnedFromWorktreeByDrop(issueId: issue.id)))

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Column helpers

    nonisolated static func columnId(forType type: String) -> String {
        orderedColumnTypes.contains(type) ? type : unknownColumnId
    }

    nonisolated static func rebuildColumns(from issues: [LinearIssue]) -> IdentifiedArrayOf<KanbanColumn> {
        let grouped = Dictionary(grouping: issues, by: { columnId(forType: $0.statusType) })
        var columns: [KanbanColumn] = orderedColumnTypes.map { type in
            KanbanColumn(
                id: type,
                name: KanbanColumn.displayName(forType: type),
                issues: grouped[type] ?? []
            )
        }
        if let unknownIssues = grouped[unknownColumnId], !unknownIssues.isEmpty {
            columns.append(KanbanColumn(
                id: unknownColumnId,
                name: KanbanColumn.displayName(forType: unknownColumnId),
                issues: unknownIssues
            ))
        }
        return IdentifiedArrayOf(uniqueElements: columns)
    }
}

// MARK: - Sync logic

nonisolated private func performSync(
    linearAPIClient: LinearAPIClient,
    databaseClient: DatabaseClient
) async throws -> MeisterFeature.SyncResult {
    async let issuesTask = linearAPIClient.fetchLabeledIssues(MeisterFeature.syncLabel)
    async let statesTask = linearAPIClient.fetchWorkflowStatesByTeam()

    let fetchedIssues = try await issuesTask
    let workflowStatesByTeam = try await statesTask
    let dbRecords = try await databaseClient.fetchImportedIssuesExcludingWorktreeQueues()

    let fetchedIds = Set(fetchedIssues.map(\.id))
    let dbIds = Set(dbRecords.map(\.linearId))

    // Orphaned: in DB but not in the fresh fetch
    let orphanedIds = dbIds.subtracting(fetchedIds)

    // Restored: previously orphaned but now present in the fetch
    let previouslyOrphaned = Set(dbRecords.filter(\.isOrphaned).map(\.linearId))
    let restoredIds = fetchedIds.intersection(previouslyOrphaned)

    // Merge fetched issues with still-orphaned DB issues so they remain visible in the kanban
    let stillOrphanedRecords = dbRecords.filter { orphanedIds.contains($0.linearId) }
    var mergedIssues = fetchedIssues
    for record in stillOrphanedRecords {
        var issue = LinearIssue(from: record)
        issue.isOrphaned = true
        mergedIssues.append(issue)
    }

    return MeisterFeature.SyncResult(
        issues: mergedIssues,
        workflowStatesByTeam: workflowStatesByTeam,
        orphanedIds: orphanedIds,
        restoredIds: restoredIds
    )
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
            teamId: teamId, teamName: teamName,
            projectName: projectName, assigneeName: assigneeName,
            priority: priority, labels: labels, description: description,
            url: url, createdAt: createdAt, updatedAt: updatedAt,
            isOrphaned: isOrphaned
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
            teamId: record.teamId,
            teamName: record.teamName,
            projectName: record.projectName,
            assigneeName: record.assigneeName,
            priority: record.priority,
            labels: decodedLabels,
            description: record.description,
            url: record.url,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isOrphaned: record.isOrphaned
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
            teamId: issue.teamId,
            teamName: issue.teamName,
            projectName: issue.projectName,
            assigneeName: issue.assigneeName,
            priority: issue.priority,
            labels: labelsJSON,
            description: issue.description,
            url: issue.url,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            importedAt: ISO8601DateFormatter().string(from: importedAt),
            sortOrder: 0,
            isOrphaned: issue.isOrphaned
        )
    }
}
