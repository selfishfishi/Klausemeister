// Klausemeister/Worktrees/WorktreeFeature.swift
import ComposableArchitecture
import Foundation
import OSLog

struct Worktree: Equatable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    var gitWorktreePath: String
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
    private static let log = Logger(subsystem: "com.klausemeister", category: "WorktreeFeature")
    @ObservableState
    struct State: Equatable {
        var worktrees: IdentifiedArrayOf<Worktree> = []
        var isCreatingWorktree: Bool = false
        var newWorktreeName: String = ""
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
            worktrees: [WorktreeRecord],
            queueItems: [WorktreeQueueItemRecord],
            issues: [ImportedIssueRecord]
        )
        case createWorktreeTapped
        case worktreeCreated(TaskResult<WorktreeRecord>)
        case confirmDeleteTapped(worktreeId: String)
        case deleteWorktreeTapped(worktreeId: String)
        case worktreeDeleted(worktreeId: String)
        case worktreeDeleteFailed(worktree: Worktree)
        case worktreeSelected(String?)
        case issueAssignedToWorktree(worktreeId: String, issue: LinearIssue)
        case issueReturnedToMeister(queueItemId: String, issueId: String, worktreeId: String)
        case issueMovedToProcessing(queueItemId: String, issueId: String, worktreeId: String)
        case issueMovedToOutbox(queueItemId: String, issueId: String, worktreeId: String)
        case queueReordered(worktreeId: String, queuePosition: String, itemIds: [String])
        case loadFailed(String)
        case assignFailed(worktreeId: String, issueId: String)
        case moveToProcessingFailed(issueId: String, worktreeId: String, issue: LinearIssue)
        case moveToOutboxFailed(issueId: String, worktreeId: String, issue: LinearIssue, fromProcessing: Bool)
        case returnToMeisterFailed(issueId: String, worktreeId: String, issue: LinearIssue)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        enum Alert: Equatable {
            case confirmDelete(worktreeId: String)
        }

        enum Delegate: Equatable {
            case issueReturnedToMeister(issue: LinearIssue)
        }
    }

    @Dependency(\.worktreeClient) var worktreeClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                state.error = nil
                return .run { send in
                    let worktrees = try await worktreeClient.fetchWorktrees()
                    var allQueueItems: [WorktreeQueueItemRecord] = []
                    for worktree in worktrees {
                        let items = try await worktreeClient.fetchQueueItems(worktree.worktreeId)
                        allQueueItems.append(contentsOf: items)
                    }
                    let issues = try await databaseClient.fetchImportedIssues()
                    await send(.worktreesLoaded(
                        worktrees: worktrees,
                        queueItems: allQueueItems,
                        issues: issues
                    ))
                } catch: { error, send in
                    await send(.loadFailed(error.localizedDescription))
                }
                .cancellable(id: "WorktreeFeature.load", cancelInFlight: true)

            case let .worktreesLoaded(worktreeRecords, queueItems, issueRecords):
                let issuesByLinearId = Dictionary(
                    uniqueKeysWithValues: issueRecords.map { ($0.linearId, LinearIssue(from: $0)) }
                )
                let queueItemsByWorktree = Dictionary(grouping: queueItems, by: \.worktreeId)

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
                return .none

            case .createWorktreeTapped:
                let name = state.newWorktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
                let worktreeName = name.isEmpty ? state.nextDefaultName : name
                state.isCreatingWorktree = true
                state.newWorktreeName = ""
                return .run { send in
                    await send(.worktreeCreated(
                        TaskResult { try await worktreeClient.createWorktree(worktreeName, "") }
                    ))
                }

            case let .worktreeCreated(.success(record)):
                state.isCreatingWorktree = false
                state.worktrees.append(Worktree(
                    id: record.worktreeId,
                    name: record.name,
                    sortOrder: record.sortOrder,
                    gitWorktreePath: record.gitWorktreePath
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

            case .alert:
                return .none

            case let .deleteWorktreeTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                if state.selectedWorktreeId == worktreeId {
                    state.selectedWorktreeId = nil
                }
                state.worktrees.remove(id: worktreeId)
                return .run { send in
                    try await worktreeClient.deleteWorktree(worktreeId)
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
                return .run { [issueId = issue.id] _ in
                    try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                } catch: { _, send in
                    await send(.assignFailed(worktreeId: worktreeId, issueId: issue.id))
                }

            case let .issueMovedToProcessing(queueItemId, issueId, worktreeId):
                var movedIssue: LinearIssue?
                if let wtIndex = state.worktrees.index(id: worktreeId),
                   let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId })
                {
                    let issue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                    state.worktrees[wtIndex].processing = issue
                    movedIssue = issue
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
                var movedIssue: LinearIssue?
                var fromProcessing = false
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    if let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId }) {
                        let issue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                        state.worktrees[wtIndex].outbox.append(issue)
                        movedIssue = issue
                    } else if let proc = state.worktrees[wtIndex].processing, proc.id == issueId {
                        state.worktrees[wtIndex].processing = nil
                        state.worktrees[wtIndex].outbox.append(proc)
                        movedIssue = proc
                        fromProcessing = true
                    }
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

            case let .issueReturnedToMeister(queueItemId, issueId, worktreeId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else { return .none }
                let returnedIssue = state.worktrees[wtIndex].inbox.first { $0.id == issueId }
                    ?? (state.worktrees[wtIndex].processing?.id == issueId
                        ? state.worktrees[wtIndex].processing : nil)
                    ?? state.worktrees[wtIndex].outbox.first { $0.id == issueId }
                guard let issue = returnedIssue else { return .none }
                state.worktrees[wtIndex].inbox.removeAll { $0.id == issueId }
                if state.worktrees[wtIndex].processing?.id == issueId {
                    state.worktrees[wtIndex].processing = nil
                }
                state.worktrees[wtIndex].outbox.removeAll { $0.id == issueId }
                return .run { send in
                    try await worktreeClient.removeFromQueue(queueItemId)
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

            case let .returnToMeisterFailed(issueId, worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.append(issue)
                }
                state.error = "Failed to return issue to Meister."
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
