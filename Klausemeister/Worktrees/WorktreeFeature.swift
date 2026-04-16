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

struct GitStats: Equatable {
    var uncommittedFiles: Int = 0
    var additions: Int = 0
    var deletions: Int = 0
    var commitsAhead: Int = 0
    var prSummary: PRSummary?

    var isEmpty: Bool {
        uncommittedFiles == 0 && additions == 0 && deletions == 0
            && commitsAhead == 0 && prSummary == nil
    }

    nonisolated init(
        from diff: GitClient.DiffStats,
        commitsAhead: Int = 0
    ) {
        uncommittedFiles = diff.uncommittedFiles
        additions = diff.additions
        deletions = diff.deletions
        self.commitsAhead = commitsAhead
    }

    nonisolated init() {}

    struct PRSummary: Equatable {
        let number: Int
        let state: PRState
    }
}

struct Worktree: Equatable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    var gitWorktreePath: String
    var repoId: String?
    var repoName: String?
    var currentBranch: String?
    var tmuxSessionStatus: TmuxSessionStatus = .unknown
    var meisterStatus: MeisterStatus = .none
    var claudeStatus: ClaudeSessionState = .offline
    var claudeStatusText: String?
    /// Live narration from `reportActivity`. Wins over the static status label
    /// while fresh; the view treats anything older than ~30s as stale.
    var claudeActivityText: String?
    var claudeActivityUpdatedAt: Date?
    var gitStats: GitStats?
    var inbox: [LinearIssue] = []
    var processing: LinearIssue?
    var outbox: [LinearIssue] = []

    var totalIssueCount: Int {
        inbox.count + (processing != nil ? 1 : 0) + outbox.count
    }

    var isActive: Bool {
        processing != nil
    }

    /// True while the meister is alive AND Claude is actively running a tool.
    /// Drives the rotating-comet swimlane border so at-a-glance you can tell
    /// which lanes are in motion.
    var isMeisterWorking: Bool {
        guard meisterStatus == .running else { return false }
        if case .working = claudeStatus { return true }
        return false
    }
}

/// Lifecycle status of the tmux session bound to a worktree. Reconciled at app
/// launch via `TmuxClient.listSessions` and updated as worktrees are created or
/// deleted. `.unknown` represents the gap between launch and the first
/// reconciliation completing.
enum TmuxSessionStatus: Equatable {
    case unknown
    case sessionExists
    case needsCreation
}

/// Lifecycle of the meister Claude Code process inside a worktree's tmux
/// session. In-memory only — not persisted across app launches — because the
/// tmux session itself is the source of truth and the meister inside it
/// re-handshakes over MCP on reconnect.
enum MeisterStatus: Equatable {
    case none
    case spawning
    case running
    case disconnected
}

/// State for the Create Worktree sheet presented from the Meister swimlane
/// header. Holds the repo pick, the free-form name, and the set of existing
/// local branches for the selected repo (used for the inline collision check).
struct CreateWorktreeSheetState: Equatable, Identifiable {
    var id: String {
        "create-worktree-sheet"
    }

    var repoId: String?
    var name: String = ""
    var existingBranches: [String] = []
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
        /// Whether the board overlay (inbox/processing/outbox columns) is
        /// showing on top of the terminal. Persisted to UserDefaults.
        var showBoardOverlay: Bool = UserDefaults.standard.bool(
            forKey: WorktreeFeature.showBoardOverlayUserDefaultsKey
        )

        /// Hello events that arrived before worktrees were loaded from DB.
        /// Replayed once `worktreesLoaded` populates the worktree array.
        var pendingHellos: Set<String> = []

        /// MCP queue events that arrived before worktrees were loaded.
        /// Replayed once `worktreesLoaded` populates the worktree array.
        var pendingQueueEvents: [MCPServerEvent] = []

        /// Which repo sections are collapsed in the swimlane view.
        var collapsedRepoIds: Set<String> = []
        /// Presented create-worktree sheet state, or nil when the sheet is hidden.
        var createSheet: CreateWorktreeSheetState?
        @Presents var alert: AlertState<Action.Alert>?

        var nextDefaultName: String {
            WorktreeDefaultName.next(excluding: Set(worktrees.map(\.name)))
        }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case claudeStatusChanged(worktreeId: String, state: ClaudeSessionState)
        case claudeStatusTextChanged(worktreeId: String, text: String)
        case claudeActivityTextChanged(worktreeId: String, text: String)
        /// Fired by the TTL effect scheduled in `claudeActivityTextChanged`
        /// to clear the activity slot once the UI ticker has hard-cut back
        /// to the static label.
        case claudeActivityExpired(worktreeId: String)
        /// Inject `slashCommand` (e.g. `/klause-next`, `/klause-review`) into
        /// the worktree's tmux session via `TmuxClient.sendKeys`. The meister
        /// reads it as if the user typed it.
        case sendSlashCommandRequested(worktreeId: String, slashCommand: String)
        /// Ask the Meister kanban to move an issue to a different state
        /// (Linear-only status change). Emitted as a delegate so the
        /// cross-feature move stays in one place.
        case moveIssueStatusRequested(issueId: String, target: MeisterState)
        case worktreesLoaded(
            repositories: [RepositoryRecord],
            worktrees: [WorktreeRecord],
            queueItems: [WorktreeQueueItemRecord],
            issues: [ImportedIssueRecord]
        )
        case createWorktreeTapped(repoId: String, name: String)
        case worktreeCreated(TaskResult<WorktreeRecord>)
        case createSheetShown(prefilledRepoId: String?)
        case createSheetDismissed
        case createSheetRepoChanged(repoId: String)
        case createSheetNameChanged(String)
        case createSheetSubmitted
        case existingBranchesLoaded(repoId: String, branches: [String])
        case existingBranchesFailed(repoId: String, error: String)
        case confirmDeleteTapped(worktreeId: String)
        case deleteWorktreeTapped(worktreeId: String)
        case worktreeDeleted(worktreeId: String)
        case worktreeDeleteFailed(worktree: Worktree)
        case removeWorktreeTapped(worktreeId: String)
        case removeWorktreeConfirmed(worktreeId: String)
        case worktreeSelected(String?)
        case boardOverlayToggled
        case repoCollapseToggled(repoId: String)
        case renameWorktreeTapped(worktreeId: String, newName: String)
        case worktreeRenamed(worktreeId: String, newName: String)
        case worktreeRenameFailed(worktreeId: String, previousName: String, error: String)
        case issueAssignedToWorktree(worktreeId: String, issue: LinearIssue)
        case markAsCompleteTapped(worktreeId: String)
        case issueReturnedToMeister(issueId: String, worktreeId: String)
        case issueMovedToProcessing(queueItemId: String, issueId: String, worktreeId: String)
        case issueMovedToOutbox(queueItemId: String, issueId: String, worktreeId: String)
        case queueReordered(worktreeId: String, queuePosition: QueuePosition, itemIds: [String])

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
        case refreshGitStatsForWorktree(worktreeId: String)
        case gitStatsLoadedForWorktree(worktreeId: String, stats: GitStats)
        case prInfoLoaded([String: GitStats.PRSummary])
        case refreshGitStats
        case refreshPRInfo
        case refreshWorktreeInfo
        case addRepoFolderSelected(URL)
        case repoAdded(TaskResult<RepositoryRecord>)
        case removeRepoTapped(repoId: String)
        case removeRepoConfirmed(repoId: String)
        case removeRepoAndKillTmuxConfirmed(repoId: String)

        // Discovery / sync
        case syncRepo(repoId: String)
        case syncAllRepos
        case repoSynced(repoId: String, TaskResult<WorktreeClient.SyncResult>)

        // Tmux session reconciliation
        case reconcileTmuxSessions
        case tmuxSessionsReconciled([String: TmuxSessionStatus])
        case shimsDiscovered([ShimDiscoveryResult])

        // Meister Claude Code lifecycle (KLA-74)
        case meisterSpawnFailed(worktreeId: String)
        case meisterHelloReceived(worktreeId: String)
        case meisterConnectionClosed(worktreeId: String)

        // MCP queue sync (KLA-107)
        case mcpItemMovedToProcessing(worktreeId: String, issueLinearId: String)
        case mcpItemMovedToOutbox(worktreeId: String, issueLinearId: String)
        case mcpItemAddedToInbox(worktreeId: String, issueLinearId: String)
        case mcpItemAddedToInboxResolved(worktreeId: String, issue: LinearIssue)

        case queueRowTapped(issueId: String)

        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        // swiftlint:disable:next nesting
        enum Alert: Equatable {
            case confirmDelete(worktreeId: String)
            case confirmRemoveWorktree(worktreeId: String)
            case confirmRemoveRepo(repoId: String)
            case confirmRemoveRepoAndKillTmux(repoId: String)
        }

        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case issueReturnedToMeister(issue: LinearIssue)
            case issueRemovedFromKanban(issueId: String)
            case errorOccurred(message: String)
            case inspectorSelectionRequested(issueId: String)
            /// Forwarded to MeisterFeature — Linear-only status change from
            /// the swimlane "Move to…" submenu.
            case moveIssueStatusRequested(issueId: String, target: MeisterState)
        }
    }

    nonisolated private enum CancelID: Hashable {
        case load
        case syncRepo(String)
        case reconcileTmux
        case meisterSpawn(String)
        case gitFSWatcher(String)
        case refreshWorktreeStats(String)
        case prInfoPoll
        case claudeStatusWatcher
        case claudeActivityExpiry(String)
    }

    /// How long an activity line lives before the reducer wipes it so
    /// snapshots (`getStatus`, debug panel) don't leak stale narration.
    /// Matches `ClaudeStatusLineView.freshness` — keep in sync.
    nonisolated private static let claudeActivityTTL: Duration = .seconds(60)

    /// How long to wait for the meister's MCP HelloFrame after a spawn before
    /// declaring the meister disconnected. A real hello from the shim normally
    /// arrives well inside this window; if it does not, either `claude` died
    /// during startup or the shell rc files blocked the send-keys input.
    nonisolated private static let meisterHelloGracePeriod: Duration = .seconds(8)

    nonisolated fileprivate static let showBoardOverlayUserDefaultsKey = "showBoardOverlay"

    @Dependency(\.worktreeClient) var worktreeClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.gitClient) var gitClient
    @Dependency(\.tmuxClient) var tmuxClient
    @Dependency(\.meisterClient) var meisterClient
    @Dependency(\.ghClient) var ghClient
    @Dependency(\.surfaceManager) var surfaceManager
    @Dependency(\.continuousClock) var clock
    @Dependency(\.mcpServerClient) var mcpServerClient
    @Dependency(\.claudeStatusClient) var claudeStatusClient
    @Dependency(\.date) var date

    /// Effect that loads the set of local branches for the given repo into the
    /// Create sheet's collision-check cache. Shared by `createSheetShown` and
    /// `createSheetRepoChanged`.
    private func loadExistingBranchesEffect(
        repoId: String, repoPath: String
    ) -> Effect<Action> {
        .run { [gitClient] send in
            do {
                let branches = try await gitClient.listBranches(repoPath)
                await send(.existingBranchesLoaded(repoId: repoId, branches: branches))
            } catch {
                await send(.existingBranchesFailed(
                    repoId: repoId, error: error.localizedDescription
                ))
            }
        }
    }

    private struct WorktreeStatsInput {
        let id: String
        let path: String
        let branch: String?
        let repoPath: String?
    }

    private static func worktreeStatsInput(
        for worktreeId: String, from state: State
    ) -> WorktreeStatsInput? {
        guard let worktree = state.worktrees[id: worktreeId] else { return nil }
        return WorktreeStatsInput(
            id: worktree.id, path: worktree.gitWorktreePath,
            branch: worktree.currentBranch,
            repoPath: worktree.repoId.flatMap { state.repositories[id: $0]?.path }
        )
    }

    private static func worktreeStatsInputs(from state: State) -> [WorktreeStatsInput] {
        state.worktrees.compactMap { worktreeStatsInput(for: $0.id, from: state) }
    }

    /// Loads local git stats for a single worktree. Each worktree gets its
    /// own cancellation ID so FS events on one worktree don't cancel
    /// in-flight work for another.
    private func loadGitStatsForWorktreeEffect(
        _ input: WorktreeStatsInput
    ) -> Effect<Action> {
        guard !input.path.isEmpty else { return .none }
        return .run { [gitClient] send in
            do {
                let diff = try await gitClient.diffStats(input.path)
                var ahead = 0
                if let repoPath = input.repoPath {
                    do {
                        let defaultBranch = try await gitClient.resolveDefaultBranch(repoPath)
                        ahead = try await gitClient.commitsAhead(input.path, defaultBranch.name)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Self.log.warning(
                            "commitsAhead failed for \(input.id): \(error.localizedDescription)"
                        )
                    }
                }
                await send(.gitStatsLoadedForWorktree(
                    worktreeId: input.id,
                    stats: GitStats(from: diff, commitsAhead: ahead)
                ))
            } catch is CancellationError {
                return
            } catch {
                Self.log.warning(
                    "diffStats failed for \(input.id): \(error.localizedDescription)"
                )
            }
        }
        .cancellable(id: CancelID.refreshWorktreeStats(input.id), cancelInFlight: true)
    }

    /// Loads git stats for all worktrees concurrently. Each worktree is
    /// independently cancellable.
    private func loadAllGitStatsEffect(from state: State) -> Effect<Action> {
        .merge(Self.worktreeStatsInputs(from: state).map { loadGitStatsForWorktreeEffect($0) })
    }

    /// Loads PR info for every worktree that has a branch. Triggered by a 60s
    /// polling timer since PR status is remote state with no local signal.
    private func loadPRInfoEffect(
        worktrees: [WorktreeStatsInput]
    ) -> Effect<Action> {
        .run { [ghClient] send in
            var map: [String: GitStats.PRSummary] = [:]
            for input in worktrees {
                guard let repoPath = input.repoPath,
                      let branch = input.branch
                else { continue }
                do {
                    if let info = try await ghClient.prForBranch(repoPath, branch) {
                        map[input.id] = GitStats.PRSummary(
                            number: info.number, state: info.state
                        )
                    }
                } catch {
                    Self.log.warning(
                        "PR lookup failed for \(branch) in \(repoPath): \(error.localizedDescription)"
                    )
                }
            }
            await send(.prInfoLoaded(map))
        }
    }

    /// Removes a repository and all its worktrees from state and the database.
    /// Non-destructive: no files are deleted from disk. Optionally kills the
    /// associated tmux sessions when `killTmux` is true.
    private func removeRepoEffect(
        state: inout State,
        repoId: String,
        killTmux: Bool
    ) -> Effect<Action> {
        guard state.repositories[id: repoId] != nil else { return .none }
        let worktreesForRepo = state.worktrees.filter { $0.repoId == repoId }
        let worktreeIds = worktreesForRepo.map(\.id)
        let tmuxSessionNames = worktreesForRepo.map { worktree in
            WorktreeConfig.tmuxSessionName(forWorktreeName: worktree.name, repoName: worktree.repoName)
        }
        for id in worktreeIds {
            state.worktrees.remove(id: id)
        }
        state.repositories.remove(id: repoId)
        state.collapsedRepoIds.remove(repoId)
        if let selectedWt = state.selectedWorktreeId, worktreeIds.contains(selectedWt) {
            state.selectedWorktreeId = nil
        }
        return .merge(
            .cancel(id: CancelID.syncRepo(repoId)),
            .merge(worktreeIds.map { .cancel(id: CancelID.meisterSpawn($0)) }),
            .merge(worktreeIds.map { .cancel(id: CancelID.gitFSWatcher($0)) }),
            .merge(worktreeIds.map { .cancel(id: CancelID.refreshWorktreeStats($0)) }),
            .run { [surfaceManager, worktreeClient, tmuxClient] _ in
                if killTmux {
                    for sessionName in tmuxSessionNames {
                        try? await tmuxClient.killSession(sessionName)
                    }
                }
                try await worktreeClient.removeRepository(repoId)
                // Destroy surfaces only after the DB write succeeds so a
                // failure + .onAppear reload doesn't leave blank terminals.
                await MainActor.run {
                    for id in worktreeIds {
                        surfaceManager.destroySurface(id)
                    }
                }
            } catch: { _, send in
                await send(.onAppear)
            }
        )
    }

    /// Transitions a worktree to `meisterStatus = .spawning` and returns the
    /// effect that spawns (or reattaches to) its meister tmux session. Called
    /// from every issue-assignment path so the first ticket landing in an
    /// empty worktree boots its meister. Idempotent at both the state level
    /// (guard on `.none`) and the tmux level (`MeisterClient.ensureRunning`
    /// short-circuits if the session already exists).
    ///
    /// The effect runs the spawn then sleeps for a grace period. If an MCP
    /// HelloFrame arrives meanwhile, `.meisterHelloReceived` cancels this
    /// effect via `CancelID.meisterSpawn`. If the sleep completes, we flip
    /// the worktree to `.disconnected` — either `claude` crashed during
    /// startup or something (e.g. a blocking shell rc prompt) consumed the
    /// send-keys input before `claude` got to run.
    private func ensureMeisterEffect(
        state: inout State,
        worktreeId: String
    ) -> Effect<Action> {
        guard let wtIndex = state.worktrees.index(id: worktreeId) else {
            return .none
        }
        guard state.worktrees[wtIndex].meisterStatus == .none else {
            return .none
        }
        let workingDirectory = state.worktrees[wtIndex].gitWorktreePath
        guard !workingDirectory.isEmpty else { return .none }
        let sessionName = WorktreeConfig.tmuxSessionName(
            forWorktreeName: state.worktrees[wtIndex].name,
            repoName: state.worktrees[wtIndex].repoName
        )
        state.worktrees[wtIndex].meisterStatus = .spawning
        return .run { [meisterClient, clock] send in
            do {
                try await meisterClient.ensureRunning(
                    worktreeId, workingDirectory, sessionName
                )
                try await clock.sleep(for: Self.meisterHelloGracePeriod)
                await send(.meisterSpawnFailed(worktreeId: worktreeId))
            } catch is CancellationError {
                // Cancelled by .meisterHelloReceived — nothing to do.
            } catch {
                await send(.meisterSpawnFailed(worktreeId: worktreeId))
            }
        }
        .cancellable(id: CancelID.meisterSpawn(worktreeId), cancelInFlight: true)
    }

    /// Activate the Terminal tab for `worktree`: ensure its meister tmux
    /// session exists (or respawn claude into a pre-existing session whose
    /// window 0 has fallen back to a shell), create the libghostty surface
    /// whose PTY attaches to that session, and arm the grace-period
    /// fallback.
    ///
    /// Sequencing matters. The surface's PTY runs `tmux attach-session -t
    /// =klause-<name>`, which fails if the session does not yet exist, so we
    /// `await meisterClient.ensureRunning(...)` first. Doing this in a single
    /// `.run` block (rather than `.concatenate(ensureMeisterEffect,
    /// createSurfaceEffect)`) is load-bearing: the latter shape gets the
    /// downstream surface-create cancelled when `meisterHelloReceived`
    /// dispatches `.cancel(id: meisterSpawn)`, leaving the Terminal tab
    /// permanently blank on the happy path.
    ///
    /// When the meister is already running or spawning from an earlier path,
    /// we skip the spawn entirely and take the non-cancellable "attach only"
    /// branch so we do not interfere with the in-flight lifecycle.
    private func terminalActivationEffect(
        state: inout State,
        worktree: Worktree
    ) -> Effect<Action> {
        let worktreeId = worktree.id
        let workingDirectory = worktree.gitWorktreePath
        let sessionName = WorktreeConfig.tmuxSessionName(forWorktreeName: worktree.name, repoName: worktree.repoName)
        // libghostty wraps the surface command in `/bin/bash --noprofile
        // --norc`, which strips the user's PATH. A bare `tmux` would fail to
        // resolve on systems where tmux lives under `/opt/homebrew/bin` etc.
        // Use the absolute path probed by `TmuxClient` at construction time.
        let tmuxPath = tmuxClient.resolvedTmuxPath() ?? "tmux"
        let command = "\(tmuxPath) attach-session -t =\(sessionName)"
        let needsSpawn = worktree.meisterStatus == .none

        guard needsSpawn else {
            return .run { [surfaceManager] _ in
                let created = await MainActor.run {
                    surfaceManager.createSurface(worktreeId, workingDirectory, command)
                }
                if created {
                    _ = await surfaceManager.focus(worktreeId)
                }
            }
        }

        guard !workingDirectory.isEmpty else { return .none }
        state.worktrees[id: worktreeId]?.meisterStatus = .spawning
        return .run { [meisterClient, surfaceManager, clock] send in
            do {
                try await meisterClient.ensureRunning(
                    worktreeId, workingDirectory, sessionName
                )
                Self.log.info("terminalActivationEffect: ensureRunning returned; creating surface")
                let created = await MainActor.run {
                    surfaceManager.createSurface(worktreeId, workingDirectory, command)
                }
                Self.log.info("terminalActivationEffect: createSurface returned \(created, privacy: .public)")
                if created {
                    _ = await surfaceManager.focus(worktreeId)
                }
                try await clock.sleep(for: Self.meisterHelloGracePeriod)
                await send(.meisterSpawnFailed(worktreeId: worktreeId))
            } catch is CancellationError {
                // Cancelled by .meisterHelloReceived — surface is already
                // created at this point if ensureRunning succeeded.
            } catch {
                Self.log.error("terminalActivationEffect: ensureRunning threw: \(error.localizedDescription, privacy: .public)")
                await send(.meisterSpawnFailed(worktreeId: worktreeId))
            }
        }
        .cancellable(id: CancelID.meisterSpawn(worktreeId), cancelInFlight: true)
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
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

                // Carry runtime state (git stats, meister/claude lifecycle,
                // tmux status, current branch, rich progress text) over from
                // the previous worktrees list so a re-fired onAppear doesn't
                // flash stale-looking "empty" rows before the background
                // refreshes catch back up. Only DB-sourced fields come from
                // the fresh record.
                let previousWorktreesByID = Dictionary(
                    uniqueKeysWithValues: state.worktrees.map { ($0.id, $0) }
                )
                state.worktrees = IdentifiedArrayOf(uniqueElements: worktreeRecords.map { record in
                    let items = queueItemsByWorktree[record.worktreeId] ?? []
                    let previous = previousWorktreesByID[record.worktreeId]
                    return Worktree(
                        id: record.worktreeId,
                        name: record.name,
                        sortOrder: record.sortOrder,
                        gitWorktreePath: record.gitWorktreePath,
                        repoId: record.repoId,
                        repoName: record.repoId.flatMap { repoNames[$0] },
                        currentBranch: previous?.currentBranch,
                        tmuxSessionStatus: previous?.tmuxSessionStatus ?? .unknown,
                        meisterStatus: previous?.meisterStatus ?? .none,
                        claudeStatus: previous?.claudeStatus ?? .offline,
                        claudeStatusText: previous?.claudeStatusText,
                        gitStats: previous?.gitStats,
                        inbox: items
                            .filter { $0.queuePosition == .inbox }
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .compactMap { issuesByLinearId[$0.issueLinearId] },
                        processing: items
                            .first { $0.queuePosition == .processing }
                            .flatMap { issuesByLinearId[$0.issueLinearId] },
                        outbox: items
                            .filter { $0.queuePosition == .outbox }
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .compactMap { issuesByLinearId[$0.issueLinearId] }
                    )
                })
                state.worktrees.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                // Replay any meisterHelloReceived events that arrived
                // before worktrees were loaded from the database.
                for worktreeId in state.pendingHellos {
                    state.worktrees[id: worktreeId]?.meisterStatus = .running
                }
                state.pendingHellos.removeAll()

                // Replay MCP queue events buffered before worktrees loaded.
                for event in state.pendingQueueEvents {
                    switch event {
                    case let .itemMovedToProcessing(worktreeId, issueLinearId):
                        if let wtIndex = state.worktrees.index(id: worktreeId),
                           let idx = state.worktrees[wtIndex].inbox.firstIndex(
                               where: { $0.id == issueLinearId }
                           )
                        {
                            let issue = state.worktrees[wtIndex].inbox.remove(at: idx)
                            state.worktrees[wtIndex].processing = issue
                        }
                    case let .itemMovedToOutbox(worktreeId, issueLinearId):
                        if let wtIndex = state.worktrees.index(id: worktreeId),
                           let proc = state.worktrees[wtIndex].processing,
                           proc.id == issueLinearId
                        {
                            state.worktrees[wtIndex].processing = nil
                            state.worktrees[wtIndex].outbox.append(proc)
                        }
                    case let .itemAddedToInbox(worktreeId, issueLinearId):
                        if let wtIndex = state.worktrees.index(id: worktreeId) {
                            let alreadyQueued = state.worktrees[wtIndex].inbox
                                .contains { $0.id == issueLinearId }
                            if !alreadyQueued, let issue = issuesByLinearId[issueLinearId] {
                                state.worktrees[wtIndex].inbox.append(issue)
                            }
                        }
                    default:
                        break
                    }
                }
                state.pendingQueueEvents.removeAll()

                let worktreePaths = state.worktrees.map { (id: $0.id, path: $0.gitWorktreePath) }
                let worktreeInfo = Self.worktreeStatsInputs(from: state)
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
                    // Initial load of local git stats (per-worktree, concurrent)
                    loadAllGitStatsEffect(from: state),
                    // Initial load of PR info
                    loadPRInfoEffect(worktrees: worktreeInfo),
                    // FS watchers: one per worktree, debounced 2s, fires per-worktree refresh
                    .merge(worktreePaths.filter { !$0.path.isEmpty }.map { entry in
                        Effect<Action>.run { [gitClient] send in
                            for await _ in gitClient.watchForChanges(entry.path) {
                                await send(.refreshGitStatsForWorktree(worktreeId: entry.id))
                            }
                        }
                        .cancellable(
                            id: CancelID.gitFSWatcher(entry.id),
                            cancelInFlight: false
                        )
                    }),
                    // 60s polling for PR info (remote state, no FS signal)
                    .run { [clock] send in
                        for await _ in clock.timer(interval: .seconds(60)) {
                            await send(.refreshPRInfo)
                        }
                    }
                    .cancellable(id: CancelID.prInfoPoll, cancelInFlight: true),
                    .run { [claudeStatusClient] send in
                        for await update in claudeStatusClient.stateChanges() {
                            await send(.claudeStatusChanged(
                                worktreeId: update.worktreeId,
                                state: update.state
                            ))
                        }
                    }
                    .cancellable(id: CancelID.claudeStatusWatcher, cancelInFlight: true),
                    .send(.syncAllRepos),
                    .send(.reconcileTmuxSessions),
                    .run { [mcpServerClient] send in
                        let results = await mcpServerClient.discoverActiveShims()
                        if !results.isEmpty {
                            await send(.shimsDiscovered(results))
                        }
                    }
                )

            case let .branchesLoaded(branches):
                for (worktreeId, branch) in branches {
                    state.worktrees[id: worktreeId]?.currentBranch = branch
                }
                return .none

            case let .branchSwitched(worktreeId, branchName):
                state.worktrees[id: worktreeId]?.currentBranch = branchName
                return .merge(
                    .send(.refreshGitStatsForWorktree(worktreeId: worktreeId)),
                    .send(.refreshPRInfo)
                )

            case let .refreshGitStatsForWorktree(worktreeId):
                guard let input = Self.worktreeStatsInput(for: worktreeId, from: state)
                else { return .none }
                return loadGitStatsForWorktreeEffect(input)

            case let .gitStatsLoadedForWorktree(worktreeId, stats):
                var merged = stats
                merged.prSummary = state.worktrees[id: worktreeId]?.gitStats?.prSummary
                state.worktrees[id: worktreeId]?.gitStats = merged
                return .none

            case let .prInfoLoaded(prInfoByWorktreeId):
                for (worktreeId, prInfo) in prInfoByWorktreeId {
                    if state.worktrees[id: worktreeId]?.gitStats == nil {
                        state.worktrees[id: worktreeId]?.gitStats = GitStats()
                    }
                    state.worktrees[id: worktreeId]?.gitStats?.prSummary = prInfo
                }
                return .none

            case .refreshGitStats:
                return loadAllGitStatsEffect(from: state)

            case .refreshPRInfo:
                return loadPRInfoEffect(
                    worktrees: Self.worktreeStatsInputs(from: state)
                )

            case .refreshWorktreeInfo:
                let worktreePaths = state.worktrees.map {
                    (id: $0.id, path: $0.gitWorktreePath)
                }
                return .merge(
                    .run { [gitClient] send in
                        var branches: [String: String] = [:]
                        for worktree in worktreePaths where !worktree.path.isEmpty {
                            if let branch = try? await gitClient.currentBranch(worktree.path) {
                                branches[worktree.id] = branch
                            }
                        }
                        await send(.branchesLoaded(branches))
                    },
                    loadAllGitStatsEffect(from: state)
                )

            case let .createWorktreeTapped(repoId, name):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let rawName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = rawName.isEmpty ? state.nextDefaultName : rawName
                let sanitized = WorktreeNameSanitizer.sanitize(fallback).value
                guard !sanitized.isEmpty else { return .none }
                state.isCreatingWorktree = true
                let repoPath = repo.path
                return .run { send in
                    let basePath = UserDefaults.standard.string(
                        forKey: WorktreeConfig.userDefaultsBasePathKey
                    ) ?? WorktreeConfig.defaultBasePath
                    let worktreePath = WorktreeConfig.worktreePath(
                        basePath: basePath, repoRoot: repoPath, name: sanitized
                    )
                    do {
                        // Authoritative collision check at submit time so we don't
                        // race with the view-level existingBranches snapshot.
                        let existing = try await gitClient.listBranches(repoPath)
                        let baseRef: String?
                        if existing.contains(sanitized) {
                            // Reuse the existing branch — no fetch, no -b.
                            baseRef = nil
                        } else {
                            let defaultBranch = try await gitClient.resolveDefaultBranch(repoPath)
                            if defaultBranch.hasOrigin {
                                try await gitClient.fetchBranch(repoPath, defaultBranch.name)
                            }
                            baseRef = defaultBranch.hasOrigin
                                ? "origin/\(defaultBranch.name)"
                                : defaultBranch.name
                        }
                        try await gitClient.addWorktree(
                            repoPath, worktreePath, sanitized, baseRef
                        )
                        do {
                            let record = try await worktreeClient.createWorktree(
                                sanitized, worktreePath, repoId
                            )
                            await send(.worktreeCreated(.success(record)))
                        } catch {
                            do {
                                try await gitClient.removeWorktree(repoPath, worktreePath)
                            } catch let rollbackError {
                                let message = rollbackError.localizedDescription
                                Self.log.error("""
                                Rollback failed after DB insert error at \
                                \(worktreePath, privacy: .public): \
                                \(message, privacy: .public). \
                                Orphan worktree may remain on disk.
                                """)
                            }
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
                    currentBranch: branch,
                    tmuxSessionStatus: .needsCreation
                ))
                state.worktrees.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                    TextState("This will permanently remove the worktree from disk.")
                }
                return .none

            case let .removeWorktreeTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                state.alert = AlertState {
                    TextState("Remove \(worktree.name)?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmRemoveWorktree(worktreeId: worktreeId)) {
                        TextState("Remove")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("\"\(worktree.name)\" will be removed from Klausemeister. The worktree on disk is not affected.")
                }
                return .none

            case let .removeWorktreeConfirmed(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                let path = worktree.gitWorktreePath
                let repoId = worktree.repoId
                if state.selectedWorktreeId == worktreeId {
                    state.selectedWorktreeId = nil
                }
                state.worktrees.remove(id: worktreeId)
                return .merge(
                    .cancel(id: CancelID.meisterSpawn(worktreeId)),
                    .cancel(id: CancelID.gitFSWatcher(worktreeId)),
                    .cancel(id: CancelID.refreshWorktreeStats(worktreeId)),
                    .run { [surfaceManager, worktreeClient] _ in
                        if let repoId {
                            try await worktreeClient.ignoreWorktreePath(path, repoId)
                        }
                        try await worktreeClient.deleteWorktree(worktreeId)
                        await MainActor.run { surfaceManager.destroySurface(worktreeId) }
                    } catch: { _, send in
                        await send(.onAppear)
                    }
                )

            case let .alert(.presented(.confirmDelete(worktreeId))):
                return .send(.deleteWorktreeTapped(worktreeId: worktreeId))

            case let .alert(.presented(.confirmRemoveWorktree(worktreeId))):
                return .send(.removeWorktreeConfirmed(worktreeId: worktreeId))

            case let .alert(.presented(.confirmRemoveRepo(repoId))):
                return .send(.removeRepoConfirmed(repoId: repoId))

            case let .alert(.presented(.confirmRemoveRepoAndKillTmux(repoId))):
                return .send(.removeRepoAndKillTmuxConfirmed(repoId: repoId))

            case .alert:
                return .none

            case let .queueRowTapped(issueId):
                return .send(.delegate(.inspectorSelectionRequested(issueId: issueId)))

            case let .deleteWorktreeTapped(worktreeId):
                guard let worktree = state.worktrees[id: worktreeId] else { return .none }
                if state.selectedWorktreeId == worktreeId {
                    state.selectedWorktreeId = nil
                }
                let worktreePath = worktree.gitWorktreePath
                let repoPath = worktree.repoId.flatMap { state.repositories[id: $0]?.path }
                let tmuxSessionName = WorktreeConfig.tmuxSessionName(forWorktreeName: worktree.name, repoName: worktree.repoName)
                state.worktrees.remove(id: worktreeId)
                return .merge(
                    .cancel(id: CancelID.gitFSWatcher(worktreeId)),
                    .cancel(id: CancelID.refreshWorktreeStats(worktreeId)),
                    .run { [surfaceManager] send in
                        // Destroy the libghostty surface FIRST. If the DB delete
                        // throws and we restore the worktree row, the stale
                        // SurfaceStore record would otherwise satisfy `create`'s
                        // idempotency guard and the Terminal tab would be blank
                        // forever. Dropping it first means the next visit to a
                        // restored row builds a fresh surface.
                        await MainActor.run { surfaceManager.destroySurface(worktreeId) }
                        try await worktreeClient.deleteWorktree(worktreeId)
                        if let repoPath, !worktreePath.isEmpty {
                            try? await gitClient.removeWorktree(repoPath, worktreePath)
                        }
                        // Soft-fail: a missing tmux session must not block deletion.
                        try? await tmuxClient.killSession(tmuxSessionName)
                        await send(.worktreeDeleted(worktreeId: worktreeId))
                    } catch: { _, send in
                        await send(.worktreeDeleteFailed(worktree: worktree))
                    }
                )

            case .worktreeDeleted:
                return .none

            case let .worktreeDeleteFailed(worktree):
                state.worktrees.append(worktree)
                state.worktrees.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                state.alert = AlertState {
                    TextState("Could not delete \(worktree.name)")
                } message: {
                    TextState("The worktree has been restored. Please try again.")
                }
                return .none

            case let .worktreeSelected(worktreeId):
                state.selectedWorktreeId = worktreeId
                if let worktreeId,
                   let worktree = state.worktrees[id: worktreeId]
                {
                    return terminalActivationEffect(state: &state, worktree: worktree)
                }
                return .none

            case .boardOverlayToggled:
                state.showBoardOverlay.toggle()
                return .run { [show = state.showBoardOverlay] _ in
                    UserDefaults.standard.set(
                        show, forKey: Self.showBoardOverlayUserDefaultsKey
                    )
                }

            case let .repoCollapseToggled(repoId):
                if state.collapsedRepoIds.contains(repoId) {
                    state.collapsedRepoIds.remove(repoId)
                } else {
                    state.collapsedRepoIds.insert(repoId)
                }
                return .none

            case let .renameWorktreeTapped(worktreeId, newName):
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let previousName = state.worktrees[id: worktreeId]?.name,
                      previousName != trimmed
                else {
                    return .none
                }
                let collision = state.worktrees.contains { other in
                    other.id != worktreeId && other.name == trimmed
                }
                if collision {
                    return .send(.delegate(.errorOccurred(
                        message: "A worktree named '\(trimmed)' already exists."
                    )))
                }
                // Optimistic update
                state.worktrees[id: worktreeId]?.name = trimmed
                return .run { send in
                    try await worktreeClient.renameWorktree(worktreeId, trimmed)
                    await send(.worktreeRenamed(worktreeId: worktreeId, newName: trimmed))
                } catch: { error, send in
                    await send(.worktreeRenameFailed(
                        worktreeId: worktreeId,
                        previousName: previousName,
                        error: error.localizedDescription
                    ))
                }

            case .worktreeRenamed:
                return .none

            case let .worktreeRenameFailed(worktreeId, previousName, message):
                state.worktrees[id: worktreeId]?.name = previousName
                return .send(.delegate(.errorOccurred(
                    message: "Failed to rename worktree: \(message)"
                )))

            case let .createSheetShown(prefilledRepoId):
                let repoId = prefilledRepoId ?? state.repositories.first?.id
                state.createSheet = CreateWorktreeSheetState(
                    repoId: repoId,
                    name: state.nextDefaultName
                )
                guard let repoId, let repo = state.repositories[id: repoId] else {
                    return .none
                }
                return loadExistingBranchesEffect(repoId: repoId, repoPath: repo.path)

            case .createSheetDismissed:
                state.createSheet = nil
                return .none

            case let .createSheetRepoChanged(repoId):
                guard state.createSheet != nil else { return .none }
                state.createSheet?.repoId = repoId
                state.createSheet?.existingBranches = []
                guard let repo = state.repositories[id: repoId] else { return .none }
                return loadExistingBranchesEffect(repoId: repoId, repoPath: repo.path)

            case let .createSheetNameChanged(name):
                state.createSheet?.name = name
                return .none

            case .createSheetSubmitted:
                guard let sheet = state.createSheet,
                      let repoId = sheet.repoId
                else {
                    return .none
                }
                let name = sheet.name
                state.createSheet = nil
                return .send(.createWorktreeTapped(repoId: repoId, name: name))

            case let .existingBranchesLoaded(repoId, branches):
                guard state.createSheet?.repoId == repoId else { return .none }
                state.createSheet?.existingBranches = branches
                return .none

            case let .existingBranchesFailed(repoId, error):
                guard state.createSheet?.repoId == repoId else { return .none }
                state.createSheet?.existingBranches = []
                return .send(.delegate(.errorOccurred(
                    message: "Failed to load branches: \(error)"
                )))

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
                let meisterEffect = ensureMeisterEffect(state: &state, worktreeId: worktreeId)
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
                    },
                    meisterEffect
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
                            let meisterEffect = ensureMeisterEffect(
                                state: &state, worktreeId: worktreeId
                            )
                            return .merge(
                                .run { _ in
                                    try await worktreeClient.removeFromQueueByIssueId(issueId, sourceId)
                                    try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                                } catch: { _, send in
                                    // Rollback: remove from target, restore to source
                                    await send(.assignFailed(worktreeId: worktreeId, issueId: issueId))
                                },
                                meisterEffect
                            )
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
                let meisterEffect = ensureMeisterEffect(state: &state, worktreeId: worktreeId)
                return .merge(
                    .run { [issueId = issue.id] _ in
                        try await worktreeClient.assignIssueToWorktree(issueId, worktreeId)
                    } catch: { _, send in
                        await send(.assignFailed(worktreeId: worktreeId, issueId: issue.id))
                    },
                    .send(.delegate(.issueRemovedFromKanban(issueId: issue.id))),
                    meisterEffect
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
                state.pendingHellos.removeAll()
                state.pendingQueueEvents.removeAll()
                return .send(.delegate(.errorOccurred(message: message)))

            case let .assignFailed(worktreeId, issueId):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.removeAll { $0.id == issueId }
                }
                return .send(.delegate(.errorOccurred(message: "Failed to assign issue to worktree.")))

            case let .moveToProcessingFailed(issueId, worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    if state.worktrees[wtIndex].processing?.id == issueId {
                        state.worktrees[wtIndex].processing = nil
                    }
                    state.worktrees[wtIndex].inbox.append(issue)
                }
                return .send(.delegate(.errorOccurred(message: "Failed to move issue to processing.")))

            case let .moveToOutboxFailed(issueId, worktreeId, issue, fromProcessing):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].outbox.removeAll { $0.id == issueId }
                    if fromProcessing {
                        state.worktrees[wtIndex].processing = issue
                    } else {
                        state.worktrees[wtIndex].inbox.append(issue)
                    }
                }
                return .send(.delegate(.errorOccurred(message: "Failed to move issue to outbox.")))

            case let .returnToMeisterFailed(_, worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    state.worktrees[wtIndex].inbox.append(issue)
                }
                return .send(.delegate(.errorOccurred(message: "Failed to return issue to Meister.")))

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

            case let .removeRepoTapped(repoId):
                guard let repo = state.repositories[id: repoId] else { return .none }
                let worktreeCount = state.worktrees.count(where: { $0.repoId == repoId })
                if worktreeCount == 0 {
                    state.alert = AlertState {
                        TextState("Remove \(repo.name)?")
                    } actions: {
                        ButtonState(role: .destructive, action: .confirmRemoveRepo(repoId: repoId)) {
                            TextState("Remove")
                        }
                        ButtonState(role: .cancel) { TextState("Cancel") }
                    } message: {
                        TextState("\"\(repo.name)\" will be removed from Klausemeister. The folder on disk is not affected.")
                    }
                    return .none
                }
                state.alert = AlertState {
                    TextState("Remove \(repo.name)?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmRemoveRepo(repoId: repoId)) {
                        TextState("Remove")
                    }
                    ButtonState(
                        role: .destructive,
                        action: .confirmRemoveRepoAndKillTmux(repoId: repoId)
                    ) {
                        TextState("Remove & Close Tmux")
                    }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                } message: {
                    TextState(
                        "\"\(repo.name)\" and its \(worktreeCount) worktree(s) remain on disk. " +
                            "\"Remove & Close Tmux\" also closes associated terminal sessions."
                    )
                }
                return .none

            case let .removeRepoConfirmed(repoId):
                return removeRepoEffect(state: &state, repoId: repoId, killTmux: false)

            case let .removeRepoAndKillTmuxConfirmed(repoId):
                return removeRepoEffect(state: &state, repoId: repoId, killTmux: true)

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
                // Repo may have been removed while sync was in flight.
                guard state.repositories[id: repoId] != nil else { return .none }
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
                if !result.inserted.isEmpty {
                    state.worktrees.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
                var cancelEffects: [Effect<Action>] = []
                for worktreeId in result.deletedWorktreeIds {
                    state.worktrees.remove(id: worktreeId)
                    if state.selectedWorktreeId == worktreeId {
                        state.selectedWorktreeId = nil
                    }
                    cancelEffects.append(.cancel(id: CancelID.gitFSWatcher(worktreeId)))
                    cancelEffects.append(.cancel(id: CancelID.refreshWorktreeStats(worktreeId)))
                }
                if !result.deletedWorktreeIds.isEmpty {
                    Self.log.info("Auto-removed \(result.deletedWorktreeIds.count) orphaned worktree(s) for repo \(repoId)")
                }
                // Background: fetch branches for new worktrees + auto-link issues
                let inserted = result.inserted
                guard !inserted.isEmpty else {
                    return cancelEffects.isEmpty ? .none : .merge(cancelEffects)
                }
                var effects: [Effect<Action>] = cancelEffects
                effects.append(.run { send in
                    var branches: [String: String] = [:]
                    for record in inserted {
                        guard !record.gitWorktreePath.isEmpty else { continue }
                        if let branch = try? await gitClient.currentBranch(record.gitWorktreePath) {
                            branches[record.worktreeId] = branch
                            if let identifier = WorktreeConfig.extractIssueIdentifier(fromBranchName: branch),
                               let issueRecord = try? await databaseClient.fetchImportedIssueByIdentifier(identifier)
                            {
                                let issue = LinearIssue(from: issueRecord)
                                await send(.issueAssignedToWorktree(worktreeId: record.worktreeId, issue: issue))
                            }
                        }
                    }
                    if !branches.isEmpty {
                        await send(.branchesLoaded(branches))
                    }
                })
                // Reconcile tmux for newly-discovered worktrees. Without
                // this, sync-imported worktrees stay `.unknown` indefinitely
                // because the boot reconciliation already ran before sync
                // completed. The CancelID makes concurrent reconciliations
                // safe — only the most recent one wins.
                effects.append(.send(.reconcileTmuxSessions))
                return .merge(effects)

            case let .repoSynced(_, .failure(error)):
                Self.log.warning("Repo sync failed: \(error.localizedDescription)")
                return .none

            // MARK: - Tmux session reconciliation

            case .reconcileTmuxSessions:
                let worktreeNames = state.worktrees.map { (id: $0.id, name: $0.name, repoName: $0.repoName) }
                guard !worktreeNames.isEmpty else { return .none }
                return .run { send in
                    let existing: Set<String>
                    do {
                        existing = try await Set(tmuxClient.listSessions())
                    } catch {
                        // tmux not installed or unreachable — leave statuses
                        // as `.unknown` so the UI does not lie about state.
                        Self.log.warning(
                            "Tmux reconciliation skipped: \(error.localizedDescription)"
                        )
                        return
                    }
                    var statuses: [String: TmuxSessionStatus] = [:]
                    for worktree in worktreeNames {
                        let sessionName = WorktreeConfig.tmuxSessionName(
                            forWorktreeName: worktree.name,
                            repoName: worktree.repoName
                        )
                        statuses[worktree.id] = existing.contains(sessionName)
                            ? .sessionExists
                            : .needsCreation
                    }
                    await send(.tmuxSessionsReconciled(statuses))
                }
                .cancellable(id: CancelID.reconcileTmux, cancelInFlight: true)

            case let .tmuxSessionsReconciled(statuses):
                for (worktreeId, status) in statuses {
                    state.worktrees[id: worktreeId]?.tmuxSessionStatus = status
                }
                return .none

            case let .shimsDiscovered(results):
                for result in results where result.status == "connected" {
                    state.worktrees[id: result.worktreeId]?.meisterStatus = .running
                }
                return .none

            case let .claudeStatusChanged(worktreeId, claudeState):
                state.worktrees[id: worktreeId]?.claudeStatus = claudeState
                // Clear stale progress text on any non-working transition — the
                // last `reportProgress` line would otherwise persist past the
                // end of the work burst that produced it.
                switch claudeState {
                case .idle, .blocked, .error, .offline:
                    state.worktrees[id: worktreeId]?.claudeStatusText = nil
                case .working:
                    break
                }
                // Activity text is session-scoped; only wipe it when the session
                // itself goes away. Idle/blocked/error can still carry ambient
                // narration ("waiting on user feedback"). Cancel the pending
                // TTL timer so it doesn't fire into an already-empty slot.
                if claudeState == .offline {
                    state.worktrees[id: worktreeId]?.claudeActivityText = nil
                    state.worktrees[id: worktreeId]?.claudeActivityUpdatedAt = nil
                    return .cancel(id: CancelID.claudeActivityExpiry(worktreeId))
                }
                return .none

            case let .claudeStatusTextChanged(worktreeId, text):
                state.worktrees[id: worktreeId]?.claudeStatusText = text
                return .none

            case let .claudeActivityTextChanged(worktreeId, text):
                state.worktrees[id: worktreeId]?.claudeActivityText = text
                state.worktrees[id: worktreeId]?.claudeActivityUpdatedAt = date.now
                // Re-arm the TTL timer: cancelInFlight ensures each fresh
                // narration resets the clock rather than stacking timers.
                return .run { send in
                    try? await clock.sleep(for: Self.claudeActivityTTL)
                    await send(.claudeActivityExpired(worktreeId: worktreeId))
                }
                .cancellable(id: CancelID.claudeActivityExpiry(worktreeId), cancelInFlight: true)

            case let .claudeActivityExpired(worktreeId):
                state.worktrees[id: worktreeId]?.claudeActivityText = nil
                state.worktrees[id: worktreeId]?.claudeActivityUpdatedAt = nil
                return .none

            case let .sendSlashCommandRequested(worktreeId, slashCommand):
                // TmuxClient.sendKeys appends the `Enter` keyword itself — do
                // not add "\r" or "\n" to `slashCommand`.
                guard let worktree = state.worktrees[id: worktreeId] else {
                    Self.log.warning(
                        "sendSlashCommand: worktree \(worktreeId) not found in state"
                    )
                    return .none
                }
                let sessionName = WorktreeConfig.tmuxSessionName(
                    forWorktreeName: worktree.name,
                    repoName: worktree.repoName
                )
                Self.log.info(
                    "sendSlashCommand: \(slashCommand) → \(sessionName)"
                )
                return .run { [tmuxClient] send in
                    do {
                        try await tmuxClient.sendKeys(sessionName, slashCommand)
                    } catch {
                        Self.log.error(
                            "sendSlashCommand failed for \(sessionName): \(String(describing: error))"
                        )
                        await send(.delegate(.errorOccurred(
                            message: "Failed to send \(slashCommand): \(error.localizedDescription)"
                        )))
                    }
                }

            case let .moveIssueStatusRequested(issueId, target):
                // Bubble up to AppFeature, which forwards to MeisterFeature
                // to update Linear state (no slash command involved).
                return .send(.delegate(.moveIssueStatusRequested(
                    issueId: issueId,
                    target: target
                )))

            // MARK: - Meister Claude Code lifecycle (KLA-74)

            case let .meisterSpawnFailed(worktreeId):
                state.worktrees[id: worktreeId]?.meisterStatus = .disconnected
                return .none

            case let .meisterHelloReceived(worktreeId):
                if state.worktrees[id: worktreeId] != nil {
                    state.worktrees[id: worktreeId]?.meisterStatus = .running
                } else {
                    // Worktrees not loaded yet — buffer for replay.
                    state.pendingHellos.insert(worktreeId)
                }
                // Cancel the grace-period fallback — we now have proof the
                // meister is alive and reachable.
                return .cancel(id: CancelID.meisterSpawn(worktreeId))

            case let .meisterConnectionClosed(worktreeId):
                // No auto-respawn (spec FR #7). Flip to disconnected; user
                // action required to restart.
                state.worktrees[id: worktreeId]?.meisterStatus = .disconnected
                return .none

            // MARK: - MCP queue sync (KLA-107)

            case let .mcpItemMovedToProcessing(worktreeId, issueLinearId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else {
                    state.pendingQueueEvents.append(
                        .itemMovedToProcessing(worktreeId: worktreeId, issueLinearId: issueLinearId)
                    )
                    return .none
                }
                if let inboxIndex = state.worktrees[wtIndex].inbox.firstIndex(
                    where: { $0.id == issueLinearId }
                ) {
                    let issue = state.worktrees[wtIndex].inbox.remove(at: inboxIndex)
                    state.worktrees[wtIndex].processing = issue
                }
                return .none

            case let .mcpItemMovedToOutbox(worktreeId, issueLinearId):
                guard let wtIndex = state.worktrees.index(id: worktreeId) else {
                    state.pendingQueueEvents.append(
                        .itemMovedToOutbox(worktreeId: worktreeId, issueLinearId: issueLinearId)
                    )
                    return .none
                }
                if let proc = state.worktrees[wtIndex].processing,
                   proc.id == issueLinearId
                {
                    state.worktrees[wtIndex].processing = nil
                    state.worktrees[wtIndex].outbox.append(proc)
                }
                return .none

            case let .mcpItemAddedToInbox(worktreeId, issueLinearId):
                guard state.worktrees.index(id: worktreeId) != nil else {
                    state.pendingQueueEvents.append(
                        .itemAddedToInbox(worktreeId: worktreeId, issueLinearId: issueLinearId)
                    )
                    return .none
                }
                let alreadyPresent = state.worktrees[id: worktreeId]?.inbox
                    .contains { $0.id == issueLinearId } == true
                    || state.worktrees[id: worktreeId]?.processing?.id == issueLinearId
                    || state.worktrees[id: worktreeId]?.outbox
                    .contains { $0.id == issueLinearId } == true
                if !alreadyPresent {
                    // DB write already happened in the enqueueItem handler —
                    // only fetch the issue record to update in-memory state.
                    return .run { [databaseClient] send in
                        if let record = try await databaseClient.fetchImportedIssue(issueLinearId) {
                            let issue = LinearIssue(from: record)
                            await send(.mcpItemAddedToInboxResolved(
                                worktreeId: worktreeId, issue: issue
                            ))
                        }
                    }
                }
                return .none

            case let .mcpItemAddedToInboxResolved(worktreeId, issue):
                if let wtIndex = state.worktrees.index(id: worktreeId) {
                    let alreadyQueued = state.worktrees[wtIndex].inbox.contains { $0.id == issue.id }
                        || state.worktrees[wtIndex].processing?.id == issue.id
                        || state.worktrees[wtIndex].outbox.contains { $0.id == issue.id }
                    if !alreadyQueued {
                        state.worktrees[wtIndex].inbox.append(issue)
                    }
                }
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
