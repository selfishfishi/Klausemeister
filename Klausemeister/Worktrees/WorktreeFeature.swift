// Klausemeister/Worktrees/WorktreeFeature.swift
import ComposableArchitecture
import Foundation

struct Worktree: Equatable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    var gitWorktreePath: String
    var inbox: [LinearIssue] = []
    var outbox: [LinearIssue] = []

    var totalIssueCount: Int { inbox.count + outbox.count }
}

@Reducer
struct WorktreeFeature {
    @ObservableState
    struct State: Equatable {
        var worktrees: IdentifiedArrayOf<Worktree> = []
        var isCreatingWorktree: Bool = false
        var newWorktreeName: String = ""
        var selectedWorktreeId: String?
        @Presents var alert: AlertState<Action.Alert>?

        var nextDefaultName: String {
            let existing = Set(worktrees.map(\.name))
            for index in 1...99 {
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
        case issueAssignedToWorktree(issueId: String, worktreeId: String)
        case issueReturnedToMeister(queueItemId: String, issueId: String, worktreeId: String)
        case issueMovedToOutbox(queueItemId: String, issueId: String, worktreeId: String)
        case queueReordered(worktreeId: String, queuePosition: String, itemIds: [String])
        case alert(PresentationAction<Alert>)

        @CasePathable
        enum Alert: Equatable {
            case confirmDelete(worktreeId: String)
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
                }
                .cancellable(id: "WorktreeFeature.load", cancelInFlight: true)

            case let .worktreesLoaded(worktreeRecords, queueItems, issueRecords):
                let issuesByLinearId = Dictionary(
                    uniqueKeysWithValues: issueRecords.map { ($0.linearId, LinearIssue(from: $0)) }
                )
                let queueItemsByWorktree = Dictionary(grouping: queueItems, by: \.worktreeId)

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

            case .worktreeCreated(.failure):
                state.isCreatingWorktree = false
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
                return .none

            case let .worktreeSelected(worktreeId):
                state.selectedWorktreeId = worktreeId
                return .none

            case let .issueAssignedToWorktree(issueId, worktreeId):
                return .run { send in
                    try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                    await send(.onAppear)
                }

            case let .issueMovedToOutbox(queueItemId, issueId, worktreeId):
                if let wtIndex = state.worktrees.index(id: worktreeId),
                   let issueIndex = state.worktrees[wtIndex].inbox.firstIndex(where: { $0.id == issueId })
                {
                    let issue = state.worktrees[wtIndex].inbox.remove(at: issueIndex)
                    state.worktrees[wtIndex].outbox.append(issue)
                }
                return .run { _ in
                    try await worktreeClient.moveToOutbox(queueItemId)
                }

            case let .issueReturnedToMeister(queueItemId, issueId, worktreeId):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.removeAll { $0.id == issueId }
                    state.worktrees[wtIndex].outbox.removeAll { $0.id == issueId }
                }
                return .run { _ in
                    try await worktreeClient.removeFromQueue(queueItemId)
                }

            case let .queueReordered(worktreeId, queuePosition, itemIds):
                return .run { _ in
                    try await worktreeClient.reorderQueue(worktreeId, queuePosition, itemIds)
                }
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
