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
        /// Stages the user has toggled off in the filter menu. The underlying
        /// `columns` still contains every stage — the view reads `visibleColumns`
        /// to apply this filter, so toggling a stage back on never loses data.
        /// Defaults to hiding `.completed` since most users don't want finished
        /// work cluttering the board.
        var hiddenStages: Set<MeisterState> = [.completed]
        var teams: [LinearTeam] = []
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
        let id: MeisterState
        var issues: [LinearIssue] = []

        var name: String {
            id.displayName
        }
    }

    nonisolated static let syncLabel = "klause"

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case refreshTapped
        case refreshLinearMetadataTapped
        case workflowStatesLoadedFromCache(WorkflowStatesByTeam, Date?)
        case syncCompleted(TaskResult<SyncResult>)
        case syncIndicatorReset
        case issueDropped(issueId: String, onColumn: MeisterState)
        case issueMoved(issueId: String, source: MeisterState, target: MeisterState)
        case moveToStatusTapped(issueId: String, target: MeisterState)
        case statusUpdateSucceeded(issueId: String)
        case statusUpdateFailed(issueId: String, restoreTo: MeisterState, originalIssue: LinearIssue)
        case removeIssueTapped(issueId: String)
        case stageVisibilityToggled(MeisterState)
        case assignIssueToWorktree(issue: LinearIssue, worktreeId: String)
        case issueReturnedFromWorktree(issue: LinearIssue)
        case removeIssueFromColumns(issueId: String)
        case issueDroppedFromWorktree(issueId: String, onColumn: MeisterState)
        case issueDroppedFromWorktreeResolved(issue: LinearIssue, onColumn: MeisterState)
        case teamsConfirmed([LinearTeam])
        case teamFilterToggled(teamId: String)
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

    private func syncEffect(shouldFetchStates: Bool, enabledTeamIds: [String] = []) -> Effect<Action> {
        .run { [linearAPIClient, databaseClient] send in
            await send(.syncCompleted(TaskResult {
                try await performSync(
                    linearAPIClient: linearAPIClient,
                    databaseClient: databaseClient,
                    fetchWorkflowStates: shouldFetchStates,
                    enabledTeamIds: enabledTeamIds
                )
            }))
        }
        .cancellable(id: "MeisterFeature.load", cancelInFlight: true)
    }

    /// On app launch: read the persisted workflow-states cache, then decide whether
    /// the network fetch is needed based on the cache's `fetchedAt` timestamp.
    /// This is sequential (read cache → decide TTL → run sync) to avoid the race
    /// where in-memory state is empty and we always fetch fresh.
    private func onAppearEffect(enabledTeamIds: [String] = []) -> Effect<Action> {
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
                    fetchWorkflowStates: shouldFetchStates,
                    enabledTeamIds: enabledTeamIds
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
                // Teams are loaded via teamsConfirmed, which also triggers
                // the initial sync. Skip syncing here if teams aren't loaded
                // yet to avoid a race with the workspace-wide fallback query.
                guard !state.teams.isEmpty else { return .none }
                state.syncStatus = .syncing
                let enabledTeamIds = state.teams.filter(\.isEnabled).map(\.id)
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    onAppearEffect(enabledTeamIds: enabledTeamIds)
                )

            case .refreshTapped:
                state.syncStatus = .syncing
                let shouldFetchStates = MeisterFeature.shouldFetchWorkflowStates(
                    lastFetched: state.workflowStatesLastFetched,
                    now: date.now
                )
                let enabledTeamIds = state.teams.filter(\.isEnabled).map(\.id)
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    syncEffect(shouldFetchStates: shouldFetchStates, enabledTeamIds: enabledTeamIds)
                )

            case .refreshLinearMetadataTapped:
                state.workflowStatesLastFetched = nil
                state.syncStatus = .syncing
                let enabledTeamIds = state.teams.filter(\.isEnabled).map(\.id)
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    syncEffect(shouldFetchStates: true, enabledTeamIds: enabledTeamIds)
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

            case let .issueMoved(issueId, source, target):
                guard let sourceColumn = state.columns[id: source],
                      let issueIndex = sourceColumn.issues.firstIndex(where: { $0.id == issueId }),
                      state.columns[id: target] != nil
                else { return .none }

                let originalIssue = sourceColumn.issues[issueIndex]
                // Resolve the team-specific workflow state for the target MeisterState.
                guard let teamStates = state.workflowStatesByTeam[originalIssue.teamId],
                      let targetLinearState = target.linearState(in: teamStates)
                else {
                    // No matching workflow state for this team — cannot move
                    return .none
                }

                let movedIssue = originalIssue.withUpdatedStatus(
                    status: targetLinearState.name,
                    statusId: targetLinearState.id,
                    statusType: targetLinearState.type
                )

                // Optimistic update
                state.columns[id: source]?.issues.remove(at: issueIndex)
                state.columns[id: target]?.issues.append(movedIssue)

                return .run { send in
                    try await linearAPIClient.updateIssueStatus(issueId, targetLinearState.id)
                    try await databaseClient.updateIssueStatus(
                        issueId, targetLinearState.name, targetLinearState.id, targetLinearState.type
                    )
                    await send(.statusUpdateSucceeded(issueId: issueId))
                } catch: { _, send in
                    await send(.statusUpdateFailed(
                        issueId: issueId,
                        restoreTo: source,
                        originalIssue: originalIssue
                    ))
                }

            case let .issueDropped(issueId, onColumn):
                if let fromColumn = state.columnContainingIssue(issueId) {
                    return .send(.issueMoved(
                        issueId: issueId,
                        source: fromColumn.id,
                        target: onColumn
                    ))
                }
                // Issue not in any column — coming from a worktree
                return .send(.issueDroppedFromWorktree(issueId: issueId, onColumn: onColumn))

            case let .moveToStatusTapped(issueId, target):
                guard let fromColumn = state.columnContainingIssue(issueId) else { return .none }
                return .send(.issueMoved(
                    issueId: issueId,
                    source: fromColumn.id,
                    target: target
                ))

            case .statusUpdateSucceeded:
                return .none

            case let .statusUpdateFailed(_, restoreTo, originalIssue):
                state.removeIssueFromAllColumns(originalIssue.id)
                state.columns[id: restoreTo]?.issues.append(originalIssue)
                return .send(.delegate(.errorOccurred(message: "Failed to update issue status")))

            case let .removeIssueTapped(issueId):
                state.removeIssueFromAllColumns(issueId)
                return .run { _ in
                    try await databaseClient.deleteImportedIssue(issueId)
                }

            case let .stageVisibilityToggled(stage):
                if state.hiddenStages.contains(stage) {
                    state.hiddenStages.remove(stage)
                } else {
                    state.hiddenStages.insert(stage)
                }
                return .none

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
                if let targetState = issue.meisterState, state.columns[id: targetState] != nil {
                    state.columns[id: targetState]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                return .none

            case let .issueDroppedFromWorktree(issueId, onColumn):
                return .run { send in
                    guard let record = try await databaseClient.fetchImportedIssue(issueId) else { return }
                    let issue = LinearIssue(from: record)
                    await send(.issueDroppedFromWorktreeResolved(issue: issue, onColumn: onColumn))
                }

            case let .issueDroppedFromWorktreeResolved(issue, onColumn):
                let alreadyPresent = state.columns.contains { $0.issues.contains { $0.id == issue.id } }
                guard !alreadyPresent else { return .none }
                if state.columns[id: onColumn] != nil {
                    state.columns[id: onColumn]?.issues.append(issue)
                } else if let targetState = issue.meisterState, state.columns[id: targetState] != nil {
                    state.columns[id: targetState]?.issues.append(issue)
                } else if let firstColumn = state.columns.first {
                    state.columns[id: firstColumn.id]?.issues.append(issue)
                }
                return .send(.delegate(.issueReturnedFromWorktreeByDrop(issueId: issue.id)))

            case let .teamsConfirmed(teams):
                state.teams = teams
                state.syncStatus = .syncing
                let shouldFetchStates = MeisterFeature.shouldFetchWorkflowStates(
                    lastFetched: state.workflowStatesLastFetched,
                    now: date.now
                )
                return .merge(
                    .send(.delegate(.syncStarted)),
                    .cancel(id: "MeisterFeature.syncIndicatorReset"),
                    syncEffect(
                        shouldFetchStates: shouldFetchStates,
                        enabledTeamIds: teams.filter(\.isEnabled).map(\.id)
                    )
                )

            case let .teamFilterToggled(teamId):
                guard let index = state.teams.firstIndex(where: { $0.id == teamId }) else {
                    return .none
                }
                state.teams[index].isHiddenFromBoard.toggle()
                let isNowHidden = state.teams[index].isHiddenFromBoard
                return .run { [databaseClient] _ in
                    try? await databaseClient.updateTeamFilterVisibility(teamId, isNowHidden)
                }

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

    static func rebuildColumns(from issues: [LinearIssue]) -> IdentifiedArrayOf<KanbanColumn> {
        var bucketed: [MeisterState: [LinearIssue]] = [:]
        for issue in issues {
            guard let state = issue.meisterState else { continue }
            bucketed[state, default: []].append(issue)
        }
        let columns = MeisterState.allCases.map { state in
            KanbanColumn(id: state, issues: bucketed[state] ?? [])
        }
        return IdentifiedArrayOf(uniqueElements: columns)
    }
}

// MARK: - Sync logic

nonisolated private func performSync(
    linearAPIClient: LinearAPIClient,
    databaseClient: DatabaseClient,
    fetchWorkflowStates: Bool,
    enabledTeamIds: [String]
) async throws -> MeisterFeature.SyncResult {
    // Fetch issues — per-team parallel when team IDs are available,
    // otherwise fall back to the workspace-wide single fetch.
    async let issuesTask: [LinearIssue] = {
        if enabledTeamIds.isEmpty {
            return try await linearAPIClient.fetchLabeledIssues(MeisterFeature.syncLabel, nil)
        }
        return try await withThrowingTaskGroup(of: [LinearIssue].self) { group in
            for teamId in enabledTeamIds {
                group.addTask {
                    do {
                        return try await linearAPIClient.fetchLabeledIssues(
                            MeisterFeature.syncLabel, teamId
                        )
                    } catch {
                        // Isolated failure — this team's issues are skipped,
                        // other teams continue. The next sync will retry.
                        return []
                    }
                }
            }
            var allIssues: [LinearIssue] = []
            var seenIds = Set<String>()
            for try await teamIssues in group {
                for issue in teamIssues where seenIds.insert(issue.id).inserted {
                    allIssues.append(issue)
                }
            }
            return allIssues
        }
    }()

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
    var hiddenTeamIds: Set<String> {
        Set(teams.filter(\.isHiddenFromBoard).map(\.id))
    }

    /// Columns the user has chosen to see. Purely view-layer filtering —
    /// `columns` still holds every stage, so toggling a stage back on reveals
    /// its existing issues without resyncing. Team filter hides issues from
    /// deselected teams while preserving column structure.
    var visibleColumns: IdentifiedArrayOf<MeisterFeature.KanbanColumn> {
        let stageFiltered = columns.filter { !hiddenStages.contains($0.id) }
        guard !hiddenTeamIds.isEmpty else { return stageFiltered }
        let teamFiltered = stageFiltered.map { column in
            var col = column
            col.issues = column.issues.filter { !hiddenTeamIds.contains($0.teamId) }
            return col
        }
        return IdentifiedArrayOf(uniqueElements: teamFiltered)
    }

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
