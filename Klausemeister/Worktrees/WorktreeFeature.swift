// swiftlint:disable file_length
// Klausemeister/Worktrees/WorktreeFeature.swift
import ComposableArchitecture
import Foundation
import OSLog

struct Repository: Equatable, Identifiable {
    let id: String
    var name: String
    var path: String
    var sortOrder: Int
}

struct Worktree: Equatable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    var gitWorktreePath: String
    var repoId: String?
    var repoName: String?
    var currentBranch: String?
    var inbox: [LinearIssue] = []
    var processing: LinearIssue?
    var outbox: [LinearIssue] = []

    var totalIssueCount: Int {
        inbox.count + (processing != nil ? 1 : 0) + outbox.count
    }

    var isActive: Bool {
        processing != nil
    }
}

@Reducer
// swiftlint:disable:next type_body_length
struct WorktreeFeature {
    nonisolated private static let log = Logger(subsystem: "com.klausemeister", category: "WorktreeFeature")
    @ObservableState
    struct State: Equatable {
        var repositories: IdentifiedArrayOf<Repository> = []
        var worktrees: IdentifiedArrayOf<Worktree> = []
        var isCreatingWorktree: Bool = false
        var selectedWorktreeId: String?
        var error: String?
        @Presents var alert: AlertState<Action.Alert>?

        var nextDefaultName: String {
            let existing = Set(worktrees.map(\.name))
            for index in 1 ... 99 {
                let candidate = "W\(index)"
                if !existing.contains(candidate) { return candidate }
            }
            return "W\(worktrees.count + 1)"
        }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case worktreesLoaded(
            repositories: [RepositoryRecord],
            worktrees: [WorktreeRecord],
            queueItems: [WorktreeQueueItemRecord],
            issues: [ImportedIssueRecord]
        )
        case createWorktreeTapped(repoId: String, name: String)
        case worktreeCreated(TaskResult<WorktreeRecord>)
        case confirmDeleteTapped(worktreeId: String)
        case deleteWorktreeTapped(worktreeId: String)
        case worktreeDeleted(worktreeId: String)
        case worktreeDeleteFailed(worktree: Worktree)
        case worktreeSelected(String?)
        case issueAssignedToWorktree(worktreeId: String, issue: LinearIssue)
        case markAsCompleteTapped(worktreeId: String)
        case issueReturnedToMeister(issueId: String, worktreeId: String)
        case issueMovedToProcessing(queueItemId: String, issueId: String, worktreeId: String)
        case issueMovedToOutbox(queueItemId: String, issueId: String, worktreeId: String)
        case queueReordered(worktreeId: String, queuePosition: String, itemIds: [String])

        // Drag-and-drop (issue-ID-based, no queueItemId needed)
        case issueDroppedOnInbox(issueId: String, worktreeId: String)
        case issueDroppedOnInboxResolved(worktreeId: String, issue: LinearIssue)
        case issueDroppedOnProcessing(issueId: String, worktreeId: String)
        case issueDroppedOnOutbox(issueId: String, worktreeId: String)
        case issueRemovedByKanbanDrop(issueId: String)

        case loadFailed(String)
        case assignFailed(worktreeId: String, issueId: String)
        case moveToProcessingFailed(issueId: String, worktreeId: String, issue: LinearIssue)
        case moveToOutboxFailed(issueId: String, worktreeId: String, issue: LinearIssue, fromProcessing: Bool)
        case returnToMeisterFailed(issueId: String, worktreeId: String, issue: LinearIssue)
        case branchSwitched(worktreeId: String, branchName: String)
        case branchesLoaded([String: String])
        case addRepoFolderSelected(URL)
        case repoAdded(TaskResult<RepositoryRecord>)
        case confirmDeleteRepoTapped(repoId: String)
        case deleteRepoConfirmed(repoId: String)

        // Discovery / sync
        case syncRepo(repoId: String)
        case syncAllRepos
        case repoSynced(repoId: String, TaskResult<WorktreeClient.SyncResult>)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        // swiftlint:disable:next nesting
        enum Alert: Equatable {
            case confirmDelete(worktreeId: String)
            case confirmDeleteRepo(repoId: String)
        }

        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case issueReturnedToMeister(issue: LinearIssue)
            case issueRemovedFromKanban(issueId: String)
        }
    }

    nonisolated private enum CancelID: Hashable {
        case load
        case syncRepo(String)
    }

    @Dependency(\.worktreeClient) var worktreeClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.gitClient) var gitClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                state.error = nil
                return .run { send in
                    let repos = try await worktreeClient.fetchRepositories()
                    let worktrees = try await worktreeClient.fetchWorktrees()
                    var allQueueItems: [WorktreeQueueItemRecord] = []
                    for worktree in worktrees {
                        let items = try await worktreeClient.fetchQueueItems(worktree.worktreeId)
                        allQueueItems.append(contentsOf: items)
                    }
                    let issues = try await databaseClient.fetchImportedIssues()
                    await send(.worktreesLoaded(
                        repositories: repos,
                        worktrees: worktrees,
                        queueItems: allQueueItems,
                        issues: issues
                    ))
                } catch: { error, send in
                    await send(.loadFailed(error.localizedDescription))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .worktreesLoaded(repoRecords, worktreeRecords, queueItems, issueRecords):
                state.repositories = IdentifiedArrayOf(uniqueElements: repoRecords.map { record in
                    Repository(id: record.repoId, name: record.name, path: record.path, sortOrder: record.sortOrder)
                })

                let issuesByLinearId = Dictionary(
                    uniqueKeysWithValues: issueRecords.map { ($0.linearId, LinearIssue(from: $0)) }
                )
                let queueItemsByWorktree = Dictionary(grouping: queueItems, by: \.worktreeId)
                let repoNames = Dictionary(uniqueKeysWithValues: repoRecords.map { ($0.repoId, $0.name) })

                let orphanedItems = queueItems.filter { issuesByLinearId[$0.issueLinearId] == nil }
                if !orphanedItems.isEmpty {
                    Self.log.warning(
                        "\(orphanedItems.count) queue item(s) reference missing issues — data may be inconsistent"
                    )
                }

                state.worktrees = IdentifiedArrayOf(uniqueElements: worktreeRecords.map { record in
                    let items = queueItemsByWorktree[record.worktreeId] ?? []
                    return Worktree(
                        id: record.worktreeId,
                        name: record.name,
                        sortOrder: record.sortOrder,
                        gitWorktreePath: record.gitWorktreePath,
                        repoId: record.repoId,
                        repoName: record.repoId.flatMap { repoNames[$0] },
                        inbox: items
                            .filter { $0.queuePosition == "inbox" }
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .compactMap { issuesByLinearId[$0.issueLinearId] },
                        processing: items
                            .first { $0.queuePosition == "processing" }
                            .flatMap { issuesByLinearId[$0.issueLinearId] },
                        outbox: items
                            .filter { $0.queuePosition == "outbox" }
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .compactMap { issuesByLinearId[$0.issueLinearId] }
                    )
                })
                let worktreePaths = state.worktrees.map { (id: $0.id, path: $0.gitWorktreePath) }
                return .merge(
                    .run { send in
                        var branches: [String: String] = [:]
                        for worktree in worktreePaths where !worktree.path.isEmpty {
                            if let branch = try? await gitClient.currentBranch(worktree.path) {
                                branches[worktree.id] = branch
                            }
                        }
                        await send(.branchesLoaded(branches))
                    },
                    .send(.syncAllRepos)
                )

            case let .branchesLoaded(branches):
                for (worktreeId, branch) in branches {
                    state.worktrees[id: worktreeId]?.currentBranch = branch
                }
                return .none

            case let .branchSwitched(worktreeId, branchName):
                state.worktrees[id: worktreeId]?.currentBranch = branchName
                return .none

            case let .createWorktreeTapped(repoId, name):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let worktreeName = trimmed.isEmpty ? state.nextDefaultName : trimmed
                state.isCreatingWorktree = true
                let repoPath = repo.path
                return .run { send in
                    let basePath = UserDefaults.standard.string(
                        forKey: WorktreeConfig.userDefaultsBasePathKey
                    ) ?? WorktreeConfig.defaultBasePath
                    let worktreePath = WorktreeConfig.worktreePath(
                        basePath: basePath, repoRoot: repoPath, name: worktreeName
                    )
                    let branch = WorktreeConfig.branchName(fromIdentifier: worktreeName)
                    do {
                        try await gitClient.addWorktree(repoPath, worktreePath, branch)
                        do {
                            let record = try await worktreeClient.createWorktree(
                                worktreeName, worktreePath, repoId
                            )
                            await send(.worktreeCreated(.success(record)))
                        } catch {
                            try? await gitClient.removeWorktree(repoPath, worktreePath)
                            await send(.worktreeCreated(.failure(error)))
                        }
                    } catch {
                        await send(.worktreeCreated(.failure(error)))
                    }
                }

            case let .worktreeCreated(.success(record)):
                state.isCreatingWorktree = false
                let repoName = record.repoId.flatMap { id in state.repositories[id: id]?.name }
                let branch = WorktreeConfig.branchName(fromIdentifier: record.name)
                state.worktrees.append(Worktree(
                    id: record.worktreeId,
                    name: record.name,
                    sortOrder: record.sortOrder,
                    gitWorktreePath: record.gitWorktreePath,
                    repoId: record.repoId,
                    repoName: repoName,
                    currentBranch: branch
                ))
                return .none

            case let .worktreeCreated(.failure(error)):
                state.isCreatingWorktree = false
                state.alert = AlertState {
                    TextState("Failed to create worktree")
                } message: {
                    TextState(error.localizedDescription)
                }
                return .none

            case let .confirmDeleteTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                if worktree.inbox.isEmpty {
                    return .send(.deleteWorktreeTapped(worktreeId: worktreeId))
                }
                state.alert = AlertState {
                    TextState("Delete \(worktree.name)?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete(worktreeId: worktreeId)) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("\(worktree.inbox.count) issue(s) in inbox will be returned to Meister.")
                }
                return .none

            case let .alert(.presented(.confirmDelete(worktreeId))):
                return .send(.deleteWorktreeTapped(worktreeId: worktreeId))

            case let .alert(.presented(.confirmDeleteRepo(repoId))):
                return .send(.deleteRepoConfirmed(repoId: repoId))

            case .alert:
                return .none

            case let .deleteWorktreeTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                if state.selectedWorktreeId == worktreeId {
                    state.selectedWorktreeId = nil
                }
                let worktreePath = worktree.gitWorktreePath
                let repoPath = worktree.repoId.flatMap { state.repositories[id: $0]?.path }
                state.worktrees.remove(id: worktreeId)
                return .run { send in
                    try await worktreeClient.deleteWorktree(worktreeId)
                    if let repoPath, !worktreePath.isEmpty {
                        try? await gitClient.removeWorktree(repoPath, worktreePath)
                    }
                    await send(.worktreeDeleted(worktreeId: worktreeId))
                } catch: { _, send in
                    await send(.worktreeDeleteFailed(worktree: worktree))
                }

            case .worktreeDeleted:
                return .none

            case let .worktreeDeleteFailed(worktree):
                state.worktrees.append(worktree)
                state.worktrees.sort { $0.sortOrder < $1.sortOrder }
                state.alert = AlertState {
                    TextState("Could not delete \(worktree.name)")
                } message: {
                    TextState("The worktree has been restored. Please try again.")
                }
                return .none

            case let .worktreeSelected(worktreeId):
                state.selectedWorktreeId = worktreeId
                return .none

            case let .issueAssignedToWorktree(worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    let alreadyQueued = state.worktrees[wtIndex].inbox.contains { $0.id == issue.id }
                        || state.worktrees[wtIndex].processing?.id == issue.id
                        || state.worktrees[wtIndex].outbox.contains { $0.id == issue.id }
                    if !alreadyQueued {
                        state.worktrees[wtIndex].inbox.append(issue)
                    }
                }
                let worktreePath = state.worktrees[id: worktreeId]?.gitWorktreePath
                return .merge(
                    .run { [issueId = issue.id] _ in
                        try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                    } catch: { _, send in
                        await send(.assignFailed(worktreeId: worktreeId, issueId: issue.id))
                    },
                    .run { send in
                        guard let path = worktreePath, !path.isEmpty else { return }
                        let branch = WorktreeConfig.branchName(fromIdentifier: issue.identifier)
                        do {
                            try await gitClient.switchBranch(path, branch)
                            await send(.branchSwitched(worktreeId: worktreeId, branchName: branch))
                        } catch {
                            Self.log.warning("Branch switch failed for \(worktreeId): \(error.localizedDescription)")
                        }
                    }
                )

            case let .markAsCompleteTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId],
                      let processing = worktree.processing else { return .none }
                let issueId = processing.id
                return .run { send in
                    if let queueItemId = try await worktreeClient.findQueueItemId(issueId, worktreeId) {
                        await send(.issueMovedToOutbox(
                            queueItemId: queueItemId, issueId: issueId, worktreeId: worktreeId
                        ))
                    }
                }

            case let .issueMovedToProcessing(queueItemId, issueId, worktreeId):
                let movedIssue: LinearIssue?
                if let wtIndex = state.worktrees.index(id: worktreeId),
                   let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId })
                {
                    let issue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                    state.worktrees[wtIndex].processing = issue
                    movedIssue = issue
                } else {
                    movedIssue = nil
                }
                return .run { _ in
                    try await worktreeClient.moveToProcessing(queueItemId)
                } catch: { _, send in
                    if let issue = movedIssue {
                        await send(.moveToProcessingFailed(
                            issueId: issueId, worktreeId: worktreeId, issue: issue
                        ))
                    }
                }

            case let .issueMovedToOutbox(queueItemId, issueId, worktreeId):
                let movedIssue: LinearIssue?
                let fromProcessing: Bool
                if let wtIndex = state.worktrees.index(id: worktreeId),
                   let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId })
                {
                    let issue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                    state.worktrees[wtIndex].outbox.append(issue)
                    movedIssue = issue
                    fromProcessing = false
                } else if let wtIndex = state.worktrees.index(id: worktreeId),
                          let proc = state.worktrees[wtIndex].processing, proc.id == issueId
                {
                    state.worktrees[wtIndex].processing = nil
                    state.worktrees[wtIndex].outbox.append(proc)
                    movedIssue = proc
                    fromProcessing = true
                } else {
                    movedIssue = nil
                    fromProcessing = false
                }
                return .run { _ in
                    try await worktreeClient.moveToOutbox(queueItemId)
                } catch: { _, send in
                    if let issue = movedIssue {
                        await send(.moveToOutboxFailed(
                            issueId: issueId, worktreeId: worktreeId,
                            issue: issue, fromProcessing: fromProcessing
                        ))
                    }
                }

            case let .issueReturnedToMeister(issueId, worktreeId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else { return .none }
                let returnedIssue = state.worktrees[wtIndex].inbox.first { $0.id == issueId }
                    ?? (state.worktrees[wtIndex].processing?.id == issueId
                        ? state.worktrees[wtIndex].processing : nil)
                    ?? state.worktrees[wtIndex].outbox.first { $0.id == issueId }
                guard let issue = returnedIssue else { return .none }
                state.removeIssueFromWorktree(issueId, worktreeId: worktreeId)
                return .run { send in
                    if let queueItemId = try await worktreeClient.findQueueItemId(issueId, worktreeId) {
                        try await worktreeClient.removeFromQueue(queueItemId)
                    }
                    await send(.delegate(.issueReturnedToMeister(issue: issue)))
                } catch: { _, send in
                    await send(.returnToMeisterFailed(
                        issueId: issueId, worktreeId: worktreeId, issue: issue
                    ))
                }

            case let .queueReordered(worktreeId, queuePosition, itemIds):
                return .run { _ in
                    try await worktreeClient.reorderQueue(worktreeId, queuePosition, itemIds)
                }

            // MARK: - Drag-and-drop handlers

            case let .issueDroppedOnInbox(issueId, worktreeId):
                // Check if issue is already in this worktree
                if let target = state.worktrees[id: worktreeId] {
                    let alreadyQueued = target.inbox.contains { $0.id == issueId }
                        || target.processing?.id == issueId
                        || target.outbox.contains { $0.id == issueId }
                    if alreadyQueued { return .none }
                }
                // Check if issue is in another worktree — find and remove it first
                for worktree in state.worktrees where worktree.id != worktreeId {
                    if worktree.inbox.contains(where: { $0.id == issueId })
                        || worktree.processing?.id == issueId
                        || worktree.outbox.contains(where: { $0.id == issueId })
                    {
                        // Issue is in another worktree; look up and move
                        if let issue = worktree.inbox.first(where: { $0.id == issueId })
                            ?? worktree.outbox.first(where: { $0.id == issueId })
                            ?? (worktree.processing?.id == issueId ? worktree.processing : nil)
                        {
                            state.removeIssueFromWorktree(issueId, worktreeId: worktree.id)
                            if let wtIndex = state.worktrees.index(id: worktreeId) {
                                state.worktrees[wtIndex].inbox.append(issue)
                            }
                            let sourceId = worktree.id
                            return .run { _ in
                                try await worktreeClient.removeFromQueueByIssueId(issueId, sourceId)
                                try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                            } catch: { _, send in
                                // Rollback: remove from target, restore to source
                                await send(.assignFailed(worktreeId: worktreeId, issueId: issueId))
                            }
                        }
                    }
                }
                // Issue is from kanban — look up from DB
                return .run { send in
                    guard let record = try await databaseClient.fetchImportedIssue(issueId) else { return }
                    let issue = LinearIssue(from: record)
                    await send(.issueDroppedOnInboxResolved(worktreeId: worktreeId, issue: issue))
                }

            case let .issueDroppedOnInboxResolved(worktreeId, issue):
                // Add to worktree inbox + remove from kanban columns (not DB)
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    let alreadyQueued = state.worktrees[wtIndex].inbox.contains { $0.id == issue.id }
                        || state.worktrees[wtIndex].processing?.id == issue.id
                        || state.worktrees[wtIndex].outbox.contains { $0.id == issue.id }
                    if !alreadyQueued {
                        state.worktrees[wtIndex].inbox.append(issue)
                    }
                }
                return .merge(
                    .run { [issueId = issue.id] _ in
                        try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                    } catch: { _, send in
                        await send(.assignFailed(worktreeId: worktreeId, issueId: issue.id))
                    },
                    .send(.delegate(.issueRemovedFromKanban(issueId: issue.id)))
                )

            case let .issueDroppedOnProcessing(issueId, worktreeId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else { return .none }
                guard state.worktrees[wtIndex].processing == nil else { return .none }
                let issue: LinearIssue
                if let inboxIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId }) {
                    issue = state.worktrees[wtIndex].inbox.remove(at: inboxIndex)
                } else if let outboxIndex = state.worktrees[wtIndex].outbox.firstIndex(where: { $0.id == issueId }) {
                    issue = state.worktrees[wtIndex].outbox.remove(at: outboxIndex)
                } else {
                    return .none
                }
                state.worktrees[wtIndex].processing = issue
                return .run { _ in
                    try await worktreeClient.moveToProcessingByIssueId(issueId, worktreeId)
                } catch: { _, send in
                    await send(.moveToProcessingFailed(issueId: issueId, worktreeId: worktreeId, issue: issue))
                }

            case let .issueDroppedOnOutbox(issueId, worktreeId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else { return .none }
                let movedIssue: LinearIssue?
                let fromProcessing: Bool
                if let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId }) {
                    movedIssue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                    fromProcessing = false
                } else if let proc = state.worktrees[wtIndex].processing, proc.id == issueId {
                    state.worktrees[wtIndex].processing = nil
                    movedIssue = proc
                    fromProcessing = true
                } else {
                    movedIssue = nil
                    fromProcessing = false
                }
                guard let issue = movedIssue else { return .none }
                state.worktrees[wtIndex].outbox.append(issue)
                return .run { _ in
                    try await worktreeClient.moveToOutboxByIssueId(issueId, worktreeId)
                } catch: { _, send in
                    await send(.moveToOutboxFailed(
                        issueId: issueId, worktreeId: worktreeId,
                        issue: issue, fromProcessing: fromProcessing
                    ))
                }

            case let .issueRemovedByKanbanDrop(issueId):
                // Find which worktree contains this issue and remove it
                for worktree in state.worktrees {
                    let found = worktree.inbox.contains { $0.id == issueId }
                        || worktree.processing?.id == issueId
                        || worktree.outbox.contains { $0.id == issueId }
                    guard found else { continue }
                    state.removeIssueFromWorktree(issueId, worktreeId: worktree.id)
                    let worktreeId = worktree.id
                    return .run { _ in
                        try await worktreeClient.removeFromQueueByIssueId(issueId, worktreeId)
                    } catch: { error, _ in
                        Self.log.warning("Failed to remove queue item for \(issueId): \(error.localizedDescription)")
                    }
                }
                return .none

            case let .loadFailed(message):
                state.error = message
                return .none

            case let .assignFailed(worktreeId, issueId):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.removeAll { $0.id == issueId }
                }
                state.error = "Failed to assign issue to worktree."
                return .none

            case let .moveToProcessingFailed(issueId, worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    if state.worktrees[wtIndex].processing?.id == issueId {
                        state.worktrees[wtIndex].processing = nil
                    }
                    state.worktrees[wtIndex].inbox.append(issue)
                }
                state.error = "Failed to move issue to processing."
                return .none

            case let .moveToOutboxFailed(issueId, worktreeId, issue, fromProcessing):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].outbox.removeAll { $0.id == issueId }
                    if fromProcessing {
                        state.worktrees[wtIndex].processing = issue
                    } else {
                        state.worktrees[wtIndex].inbox.append(issue)
                    }
                }
                state.error = "Failed to move issue to outbox."
                return .none

            case let .returnToMeisterFailed(_, worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.append(issue)
                }
                state.error = "Failed to return issue to Meister."
                return .none

            case let .addRepoFolderSelected(url):
                return .run { send in
                    await send(.repoAdded(TaskResult {
                        let repoRoot = try await gitClient.repositoryRoot(url.path)
                        let name = URL(fileURLWithPath: repoRoot).lastPathComponent
                        return try await worktreeClient.addRepository(name, repoRoot)
                    }))
                }

            case let .repoAdded(.success(record)):
                let repo = Repository(
                    id: record.repoId,
                    name: record.name,
                    path: record.path,
                    sortOrder: record.sortOrder
                )
                state.repositories.append(repo)
                return .send(.syncRepo(repoId: record.repoId))

            case .repoAdded(.failure):
                state.alert = AlertState {
                    TextState("Could Not Add Repository")
                } actions: {
                    ButtonState(role: .cancel) { TextState("OK") }
                } message: {
                    TextState("The selected folder is not a valid git repository.")
                }
                return .none

            case let .confirmDeleteRepoTapped(repoId):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let worktreeCount = state.worktrees.count(where: { $0.repoId == repoId })
                if worktreeCount == 0 {
                    return .send(.deleteRepoConfirmed(repoId: repoId))
                }
                state.alert = AlertState {
                    TextState("Remove \(repo.name)?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeleteRepo(repoId: repoId)) {
                        TextState("Remove")
                    }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                } message: {
                    TextState("\(worktreeCount) worktree(s) will also be removed.")
                }
                return .none

            case let .deleteRepoConfirmed(repoId):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let worktreePaths = state.worktrees
                    .filter { $0.repoId == repoId }
                    .map(\.gitWorktreePath)
                let worktreeIds = state.worktrees.filter { $0.repoId == repoId }.map(\.id)
                for id in worktreeIds {
                    state.worktrees.remove(id: id)
                }
                state.repositories.remove(id: repoId)
                if let selectedWt = state.selectedWorktreeId, worktreeIds.contains(selectedWt) {
                    state.selectedWorktreeId = nil
                }
                let repoPath = repo.path
                return .run { _ in
                    for path in worktreePaths where !path.isEmpty {
                        try? await gitClient.removeWorktree(repoPath, path)
                    }
                    try await worktreeClient.removeRepository(repoId)
                } catch: { _, send in
                    await send(.onAppear)
                }

            // MARK: - Discovery / sync handlers

            case .syncAllRepos:
                let repoIds = state.repositories.map(\.id)
                return .merge(repoIds.map { Effect.send(.syncRepo(repoId: $0)) })

            case let .syncRepo(repoId):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let repoPath = repo.path
                return .run { send in
                    let entries = try await gitClient.listWorktrees(repoPath)
                    let filtered = entries.filter { !$0.isMain && !$0.isPrunable }
                    let result = try await worktreeClient.syncWorktreesForRepo(repoId, filtered)
                    await send(.repoSynced(repoId: repoId, .success(result)))
                } catch: { error, send in
                    await send(.repoSynced(repoId: repoId, .failure(error)))
                }
                .cancellable(id: CancelID.syncRepo(repoId), cancelInFlight: true)

            case let .repoSynced(repoId, .success(result)):
                let repoName = state.repositories[id: repoId]?.name
                // Apply diff to in-memory state
                for record in result.inserted {
                    state.worktrees.append(Worktree(
                        id: record.worktreeId,
                        name: record.name,
                        sortOrder: record.sortOrder,
                        gitWorktreePath: record.gitWorktreePath,
                        repoId: record.repoId,
                        repoName: repoName
                    ))
                }
                for worktreeId in result.deletedWorktreeIds {
                    state.worktrees.remove(id: worktreeId)
                    if state.selectedWorktreeId == worktreeId {
                        state.selectedWorktreeId = nil
                    }
                }
                if !result.deletedWorktreeIds.isEmpty {
                    Self.log.info("Auto-removed \(result.deletedWorktreeIds.count) orphaned worktree(s) for repo \(repoId)")
                }
                // Background: fetch branches for new worktrees + auto-link issues
                let inserted = result.inserted
                guard !inserted.isEmpty else { return .none }
                return .run { send in
                    var branches: [String: String] = [:]
                    for record in inserted {
                        guard !record.gitWorktreePath.isEmpty else { continue }
                        if let branch = try? await gitClient.currentBranch(record.gitWorktreePath) {
                            branches[record.worktreeId] = branch
                            if let identifier = WorktreeConfig.extractIssueIdentifier(fromBranchName: branch),
                               let issueRecord = try? await databaseClient.fetchImportedIssueByIdentifier(identifier)
                            {
                                // Use the issueAssignedToWorktree action which both updates state
                                // and persists via worktreeClient.assignIssueToWorktree
                                let issue = LinearIssue(from: issueRecord)
                                await send(.issueAssignedToWorktree(worktreeId: record.worktreeId, issue: issue))
                            }
                        }
                    }
                    if !branches.isEmpty {
                        await send(.branchesLoaded(branches))
                    }
                }

            case let .repoSynced(_, .failure(error)):
                Self.log.warning("Repo sync failed: \(error.localizedDescription)")
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

// MARK: - State Helpers

extension WorktreeFeature.State {
    mutating func removeIssueFromWorktree(_ issueId: String, worktreeId: String) {
        guard let wtIndex = worktrees.index(id: worktreeId) else { return }
        worktrees[wtIndex].inbox.removeAll { $0.id == issueId }
        if worktrees[wtIndex].processing?.id == issueId {
            worktrees[wtIndex].processing = nil
        }
        worktrees[wtIndex].outbox.removeAll { $0.id == issueId }
    }

    var assignedWorktreeNames: [String: String] {
        Dictionary(
            worktrees.flatMap { worktree in
                let allIssueIds = worktree.inbox.map(\.id)
                    + (worktree.processing.map { [$0.id] } ?? [])
                    + worktree.outbox.map(\.id)
                return allIssueIds.map { ($0, worktree.name) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
