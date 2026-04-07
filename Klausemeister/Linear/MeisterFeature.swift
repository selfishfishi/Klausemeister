// swiftlint:disable file_length
import ComposableArchitecture
import Foundation

@Reducer
// swiftlint:disable:next type_body_length
struct MeisterFeature {
    @ObservableState
    struct State: Equatable {
        var columns: IdentifiedArrayOf<KanbanColumn> = []
        var workflowStatesByTeam: WorkflowStatesByTeam = [:]
        var workflowStatesLastFetched: Date?
        var syncStatus: SyncStatus = .idle
    }

    nonisolated static let workflowStatesCacheTTL: TimeInterval = 15 * 60

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case succeeded
    }

    struct SyncResult: Equatable {
        let issues: [LinearIssue]
        /// Non-nil only when the workflow-states cache was refreshed during this sync.
        let workflowStatesByTeam: WorkflowStatesByTeam?
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
        case refreshLinearMetadataTapped
        case workflowStatesLoadedFromCache(WorkflowStatesByTeam, Date?)
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

        @CasePathable
        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case issueAssignedToWorktree(issue: LinearIssue, worktreeId: String)
            case issueReturnedFromWorktreeByDrop(issueId: String)
            case syncStarted
            case syncSucceeded
            case syncFailed(message: String)
            case errorOccurred(message: String)
        }
    }

    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.date) var date
    @Dependency(\.continuousClock) var clock

    private func syncEffect(shouldFetchStates: Bool) -> Effect<Action> {
        .run { [linearAPIClient, databaseClient] send in
            await send(.syncCompleted(TaskResult {
                try await performSync(
                    linearAPIClient: linearAPIClient,
                    databaseClient: databaseClient,
                    fetchWorkflowStates: shouldFetchStates
                )
            }))
        }
        .cancellable(id: "MeisterFeature.load", cancelInFlight: true)
    }

    /// On app launch: read the persisted workflow-states cache, then decide whether
    /// the network fetch is needed based on the cache's `fetchedAt` timestamp.
    /// This is sequential (read cache → decide TTL → run sync) to avoid the race
    /// where in-memory state is empty and we always fetch fresh.
    private func onAppearEffect() -> Effect<Action> {
        .run { [linearAPIClient, databaseClient, currentNow = date.now] send in
            // 1. Load persisted cache (if any)
            let records = await (try? databaseClient.fetchWorkflowStates()) ?? []
            var cachedFetchedAt: Date?
            if !records.isEmpty {
                let grouped = Dictionary(grouping: records, by: \.teamId)
                let cachedStates: WorkflowStatesByTeam = grouped.mapValues { rows in
                    rows.map { LinearWorkflowState(
                        id: $0.id,
                        name: $0.name,
                        type: $0.type,
                        position: $0.position,
                        teamId: $0.teamId
                    ) }.sorted { $0.position < $1.position }
                }
                let isoFormatter = ISO8601DateFormatter()
                cachedFetchedAt = records.first.flatMap { isoFormatter.date(from: $0.fetchedAt) }
                await send(.workflowStatesLoadedFromCache(cachedStates, cachedFetchedAt))
            }

            // 2. Decide whether to refetch states based on the cached timestamp
            let shouldFetchStates = MeisterFeature.shouldFetchWorkflowStates(
                lastFetched: cachedFetchedAt,
                now: currentNow
            )

            // 3. Run the sync
            await send(.syncCompleted(TaskResult {
                try await performSync(
                    linearAPIClient: linearAPIClient,
                    databaseClient: databaseClient,
                    fetchWorkflowStates: shouldFetchStates
                )
            }))
        }
        .cancellable(id: "MeisterFeature.load", cancelInFlight: true)
    }

    nonisolated static func shouldFetchWorkflowStates(lastFetched: Date?, now: Date) -> Bool {
        guard let lastFetched else { return true }
        return now.timeIntervalSince(lastFetched) >= workflowStatesCacheTTL
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                state.syncStatus = .syncing
                // First launch: must read persisted cache + check its timestamp before
                // deciding whether the network states fetch is needed. This is sequential
                // to avoid the race where in-memory state is empty and we always fetch.
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    onAppearEffect()
                )

            case .refreshTapped:
                state.syncStatus = .syncing
                let shouldFetchStates = MeisterFeature.shouldFetchWorkflowStates(
                    lastFetched: state.workflowStatesLastFetched,
                    now: date.now
                )
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    syncEffect(shouldFetchStates: shouldFetchStates)
                )

            case .refreshLinearMetadataTapped:
                state.workflowStatesLastFetched = nil
                state.syncStatus = .syncing
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    syncEffect(shouldFetchStates: true)
                )

            case let .workflowStatesLoadedFromCache(states, fetchedAt):
                // Only apply if we don't already have a fresher in-memory copy
                if state.workflowStatesByTeam.isEmpty {
                    state.workflowStatesByTeam = states
                    state.workflowStatesLastFetched = fetchedAt
                }
                return .none

            case let .syncCompleted(.success(result)):
                let now = date.now
                if let freshStates = result.workflowStatesByTeam {
                    state.workflowStatesByTeam = freshStates
                    state.workflowStatesLastFetched = now
                }
                state.columns = MeisterFeature.rebuildColumns(from: result.issues)
                state.syncStatus = .succeeded
                let records = result.issues.map { ImportedIssueRecord(from: $0, importedAt: now) }
                let workflowRecordsToSave: [LinearWorkflowStateRecord]? = result.workflowStatesByTeam.map { states in
                    let timestamp = ISO8601DateFormatter().string(from: now)
                    return states.values.flatMap(\.self).map { state in
                        LinearWorkflowStateRecord(
                            id: state.id,
                            teamId: state.teamId,
                            name: state.name,
                            type: state.type,
                            position: state.position,
                            fetchedAt: timestamp
                        )
                    }
                }
                return .merge(
                    .send(.delegate(.syncSucceeded)),
                    .run { [databaseClient] send in
                        do {
                            try await databaseClient.batchSaveImportedIssues(records)
                        } catch {
                            await send(.delegate(.errorOccurred(
                                message: "Failed to save sync results: \(error.localizedDescription)"
                            )))
                        }
                    },
                    .run { [databaseClient] _ in
                        if let workflowRecordsToSave {
                            try? await databaseClient.saveWorkflowStates(workflowRecordsToSave)
                        }
                    },
                    .run { [clock] send in
                        try await clock.sleep(for: .seconds(2))
                        await send(.syncIndicatorReset)
                    }
                    .cancellable(id: "MeisterFeature.syncIndicatorReset", cancelInFlight: true)
                )

            case let .syncCompleted(.failure(error)):
                state.syncStatus = .idle
                return .send(.delegate(.syncFailed(message: MeisterFeature.describe(error))))

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
                return .send(.delegate(.errorOccurred(message: "Failed to update issue status")))

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

    // MARK: - Error formatting

    /// Produces a human-readable description of a sync error that preserves
    /// enough detail to diagnose the failure. For `LocalizedError`, uses
    /// `errorDescription`; for `DecodingError`, uses `String(describing:)`
    /// which includes the full coding path.
    nonisolated static func describe(_ error: any Error) -> String {
        if let decodingError = error as? DecodingError {
            return String(describing: decodingError)
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    // MARK: - Column helpers

    nonisolated static func columnId(forType type: String) -> String {
        orderedColumnTypes.contains(type) ? type : unknownColumnId
    }

    static func rebuildColumns(from issues: [LinearIssue]) -> IdentifiedArrayOf<KanbanColumn> {
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
    databaseClient: DatabaseClient,
    fetchWorkflowStates: Bool
) async throws -> MeisterFeature.SyncResult {
    async let issuesTask = linearAPIClient.fetchLabeledIssues(MeisterFeature.syncLabel)
    async let statesTask: WorkflowStatesByTeam? = {
        guard fetchWorkflowStates else { return nil }
        return try await linearAPIClient.fetchWorkflowStatesByTeam()
    }()

    let fetchedIssues = try await issuesTask
    let workflowStatesByTeam = try await statesTask
    let dbRecords = try await databaseClient.fetchUnqueuedImportedIssues()

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
            teamId: teamId,
            projectName: projectName,
            labels: labels, description: description,
            url: url, updatedAt: updatedAt,
            isOrphaned: isOrphaned
        )
    }
}

// MARK: - Record Conversions

extension LinearIssue {
    nonisolated init(from record: ImportedIssueRecord) {
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
            projectName: record.projectName,
            labels: decodedLabels,
            description: record.description,
            url: record.url,
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
            projectName: issue.projectName,
            labels: labelsJSON,
            description: issue.description,
            url: issue.url,
            updatedAt: issue.updatedAt,
            importedAt: ISO8601DateFormatter().string(from: importedAt),
            sortOrder: 0,
            isOrphaned: issue.isOrphaned
        )
    }
}
