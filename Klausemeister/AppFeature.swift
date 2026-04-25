// swiftlint:disable file_length
import ComposableArchitecture
import Foundation

@Reducer
// swiftlint:disable:next type_body_length
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var showSidebar: Bool = true
        var showInspector: Bool = false
        var inspectorSelection: InspectorSelection?
        var inspectorDetail: InspectorDetailLoadState = .empty
        var showMeister: Bool = true
        var meister = MeisterFeature.State()
        var worktree = WorktreeFeature.State()
        var linearAuth = LinearAuthFeature.State()
        var statusBar = StatusBarFeature.State()
        var debugPanel = DebugPanelFeature.State()
        @Presents var teamSettings: TeamSettingsFeature.State?
        var commandPalette: CommandPaletteFeature.State?
        @Presents var shortcutCenter: ShortcutCenterFeature.State?
        var worktreeSwitcher: WorktreeSwitcherFeature.State?
        var keyBindings: [AppCommand: KeyBinding] = [:]
        /// Schedule UUID currently presented as a gantt overlay, or `nil`.
        var presentedScheduleId: String?
    }

    enum Action {
        case onAppear
        case toggleSidebar
        case toggleInspector
        case inspectorSelectionRequested(issueId: String)
        case inspectorDetailFetched(Result<InspectorTicketDetail, InspectorFetchError>)
        case themeChanged(AppTheme)
        case initialThemeSeeded(AppTheme)
        case oauthCallbackReceived(URL)
        case showMeister
        case meister(MeisterFeature.Action)
        case worktree(WorktreeFeature.Action)
        case linearAuth(LinearAuthFeature.Action)
        case statusBar(StatusBarFeature.Action)
        case debugPanel(DebugPanelFeature.Action)
        case teamSettingsButtonTapped
        case teamSettings(PresentationAction<TeamSettingsFeature.Action>)
        case openCommandPalette
        case commandPalette(CommandPaletteFeature.Action)
        case openShortcutCenter
        case shortcutCenter(PresentationAction<ShortcutCenterFeature.Action>)
        case openWorktreeSwitcher
        case worktreeSwitcher(WorktreeSwitcherFeature.Action)
        case selectWorktreeByPosition(Int)
        case keyBindingsLoaded([AppCommand: KeyBinding?])
        case mcpServerEvent(MCPServerEvent)
        case ganttOverlayDismissed
        case ganttRunTapped(scheduleId: String)
        case ganttFinishTapped(scheduleId: String)
    }

    nonisolated private enum CancelID {
        case mcpServer
        case inspectorFetch
    }

    @Dependency(\.actionRegistry) var actionRegistry
    @Dependency(\.keyBindingsClient) var keyBindingsClient
    @Dependency(\.surfaceManager) var surfaceManager
    @Dependency(\.ghosttyApp) var ghosttyApp
    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.mcpServerClient) var mcpServerClient
    @Dependency(\.linearAPIClient) var linearAPIClient

    var body: some Reducer<State, Action> {
        Scope(state: \.meister, action: \.meister) {
            MeisterFeature()
        }
        Scope(state: \.worktree, action: \.worktree) {
            WorktreeFeature()
        }
        Scope(state: \.linearAuth, action: \.linearAuth) {
            LinearAuthFeature()
        }
        Scope(state: \.statusBar, action: \.statusBar) {
            StatusBarFeature()
        }
        Scope(state: \.debugPanel, action: \.debugPanel) {
            DebugPanelFeature()
        }
        .ifLet(\.$teamSettings, action: \.teamSettings) {
            TeamSettingsFeature()
        }
        .ifLet(\.commandPalette, action: \.commandPalette) {
            CommandPaletteFeature()
        }
        .ifLet(\.$shortcutCenter, action: \.shortcutCenter) {
            ShortcutCenterFeature()
        }
        .ifLet(\.worktreeSwitcher, action: \.worktreeSwitcher) {
            WorktreeSwitcherFeature()
        }
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.keyBindings = actionRegistry.resolvedBindings()
                return .merge(
                    .run(priority: .utility) { [keyBindingsClient] send in
                        let overrides = await (try? keyBindingsClient.loadOverrides()) ?? [:]
                        await send(.keyBindingsLoaded(overrides))
                    },
                    .run(priority: .utility) { [mcpServerClient] _ in
                        await mcpServerClient.start()
                    }
                    .cancellable(id: CancelID.mcpServer),
                    .run(priority: .utility) { [mcpServerClient] send in
                        for await event in mcpServerClient.events() {
                            await send(.mcpServerEvent(event))
                        }
                    }
                    .cancellable(id: CancelID.mcpServer)
                )

            case .showMeister:
                state.showMeister = true
                state.worktree.selectedWorktreeId = nil
                return .none

            case let .meister(.delegate(.issueAssignedToWorktree(issue, worktreeId))):
                return .send(.worktree(.issueAssignedToWorktree(
                    worktreeId: worktreeId,
                    issue: issue
                )))

            case let .meister(.delegate(.issueReturnedFromWorktreeByDrop(issueId))):
                return .send(.worktree(.issueRemovedByKanbanDrop(issueId: issueId)))

            case .meister(.delegate(.syncStarted)):
                return .send(.statusBar(.syncStateChanged(true)))

            case .meister(.delegate(.syncSucceeded)):
                return .merge(
                    .send(.statusBar(.syncStateChanged(false))),
                    .send(.statusBar(.errorClearedForSource(.sync)))
                )

            case let .meister(.delegate(.syncPartiallyFailed(failures, teamNames))):
                let infos = failures.map { failure in
                    StatusBarFeature.TeamFailureInfo(
                        teamKey: teamNames[failure.teamId] ?? failure.teamId,
                        message: failure.message
                    )
                }
                return .merge(
                    .send(.statusBar(.syncStateChanged(false))),
                    .send(.statusBar(.errorClearedForSource(.sync))),
                    .send(.statusBar(.teamErrorsReported(infos)))
                )

            case let .meister(.delegate(.syncFailed(message))):
                return .merge(
                    .send(.statusBar(.syncStateChanged(false))),
                    .send(.statusBar(.errorReported(source: .sync, message: message)))
                )

            case let .meister(.delegate(.errorOccurred(message))):
                return .send(.statusBar(.errorReported(source: .meister, message: message)))

            case let .meister(.delegate(.inspectorSelectionRequested(issueId))):
                return .send(.inspectorSelectionRequested(issueId: issueId))

            case .meister:
                return .none

            case .worktree(.worktreeSelected(.some)):
                state.showMeister = false
                return .none

            case let .worktree(.delegate(.issueReturnedToMeister(issue))):
                return .send(.meister(.issueReturnedFromWorktree(issue: issue)))

            case let .worktree(.delegate(.issueRemovedFromKanban(issueId))):
                return .send(.meister(.removeIssueFromColumns(issueId: issueId)))

            case let .worktree(.delegate(.errorOccurred(message))):
                return .send(.statusBar(.errorReported(source: .worktree, message: message)))

            case let .worktree(.delegate(.inspectorSelectionRequested(issueId))):
                return .send(.inspectorSelectionRequested(issueId: issueId))

            case let .worktree(.delegate(.moveIssueStatusRequested(issueId, target))):
                return .send(.meister(.moveToStatusTapped(issueId: issueId, target: target)))

            case let .worktree(.delegate(.scheduleTapped(scheduleId))):
                state.presentedScheduleId = scheduleId
                return .none

            case .ganttOverlayDismissed:
                state.presentedScheduleId = nil
                return .none

            case let .ganttRunTapped(scheduleId):
                return .send(.worktree(.runScheduleTapped(scheduleId: scheduleId)))

            case let .ganttFinishTapped(scheduleId):
                // Dismiss overlay if the finished schedule is the one on
                // screen, then hand off to worktree to purge state + DB.
                if state.presentedScheduleId == scheduleId {
                    state.presentedScheduleId = nil
                }
                return .send(.worktree(.finishScheduleTapped(scheduleId: scheduleId)))

            case .worktree:
                return .none

            case .toggleSidebar:
                state.showSidebar.toggle()
                return .none

            case .toggleInspector:
                state.showInspector.toggle()
                return .none

            case let .inspectorSelectionRequested(issueId):
                state.inspectorSelection = .ticket(id: issueId)
                state.showInspector = true
                state.inspectorDetail = .loading
                return .run { [linearAPIClient] send in
                    do {
                        let detail = try await linearAPIClient.fetchTicketDetail(issueId)
                        await send(.inspectorDetailFetched(.success(detail)))
                    } catch is CancellationError {
                        // A newer selection owns state; don't overwrite with an error.
                    } catch {
                        await send(.inspectorDetailFetched(
                            .failure(InspectorFetchError.from(error))
                        ))
                    }
                }
                .cancellable(id: CancelID.inspectorFetch, cancelInFlight: true)

            case let .inspectorDetailFetched(result):
                switch result {
                case let .success(detail):
                    state.inspectorDetail = .loaded(detail)
                case let .failure(err):
                    state.inspectorDetail = .error(err)
                }
                return .none

            case let .themeChanged(theme):
                // Hot-reload via ghostty_app_update_config (KLA-173):
                // app handle is stable across theme swaps, so we no longer
                // need the destroy-surfaces / free-app / new-app / restore
                // dance. Surfaces don't auto-inherit app config updates,
                // so we explicitly push the new config to each.
                return .run { _ in
                    await MainActor.run {
                        ghosttyApp.rebuild(theme)
                        if let config = ghosttyApp.config() {
                            surfaceManager.applyConfigToAll(config)
                        }
                    }
                }

            case let .initialThemeSeeded(theme):
                // Primes libghostty with the persisted theme on first window
                // appearance; no surfaces exist yet so skip recreation.
                return .run { _ in
                    await MainActor.run { ghosttyApp.rebuild(theme) }
                }

            case let .oauthCallbackReceived(url):
                return .run { [oauthClient] _ in
                    oauthClient.handleCallback(url)
                }

            case let .linearAuth(.delegate(.teamsConfirmed(teams))):
                state.linearAuth.status = .authenticated
                return .send(.meister(.teamsConfirmed(teams)))

            case let .linearAuth(.delegate(.errorOccurred(message))):
                return .send(.statusBar(.errorReported(source: .linearAuth, message: message)))

            case .linearAuth:
                return .none

            case .openCommandPalette:
                state.commandPalette = CommandPaletteFeature.State(
                    keyBindings: state.keyBindings
                )
                return .none

            case let .commandPalette(.delegate(.commandInvoked(command))):
                state.commandPalette = nil
                return executeCommand(command, state: &state)

            case .commandPalette(.delegate(.dismissed)):
                state.commandPalette = nil
                return .none

            case .commandPalette:
                return .none

            case let .keyBindingsLoaded(overrides):
                for (command, binding) in overrides {
                    if let binding {
                        state.keyBindings[command] = binding
                    } else {
                        // nil = user explicitly cleared this shortcut
                        state.keyBindings.removeValue(forKey: command)
                    }
                }
                return .none

            case .openShortcutCenter:
                state.shortcutCenter = ShortcutCenterFeature.State(
                    keyBindings: state.keyBindings
                )
                return .none

            case let .shortcutCenter(.presented(.delegate(.bindingsSaved(newBindings)))):
                state.shortcutCenter = nil
                state.keyBindings = newBindings
                return .none

            case .shortcutCenter(.presented(.delegate(.dismissed))):
                state.shortcutCenter = nil
                return .none

            case .shortcutCenter:
                return .none

            case .openWorktreeSwitcher:
                state.commandPalette = nil
                state.worktreeSwitcher = WorktreeSwitcherFeature.State(
                    worktrees: Array(state.worktree.worktrees)
                )
                return .none

            case let .worktreeSwitcher(.delegate(.itemSelected(item))):
                state.worktreeSwitcher = nil
                switch item {
                case .meister:
                    state.showMeister = true
                    state.worktree.selectedWorktreeId = nil
                case let .worktree(worktreeId, _, _):
                    state.showMeister = false
                    return .send(.worktree(.worktreeSelected(worktreeId)))
                }
                return .none

            case .worktreeSwitcher(.delegate(.dismissed)):
                state.worktreeSwitcher = nil
                return .none

            case .worktreeSwitcher:
                return .none

            case let .selectWorktreeByPosition(position):
                let worktrees = state.worktree.worktrees
                guard position >= 1, position <= worktrees.count else { return .none }
                let worktreeId = worktrees[position - 1].id
                state.showMeister = false
                return .send(.worktree(.worktreeSelected(worktreeId)))

            case .teamSettingsButtonTapped:
                state.teamSettings = TeamSettingsFeature.State()
                return .none

            case let .teamSettings(.presented(.delegate(.teamsUpdated(teams)))):
                state.teamSettings = nil
                return .merge(
                    .send(.meister(.teamsConfirmed(teams))),
                    .send(.worktree(.onAppear))
                )

            case .teamSettings(.presented(.delegate(.dismissed))):
                state.teamSettings = nil
                return .none

            case .teamSettings:
                return .none

            case .statusBar:
                return .none

            case .debugPanel:
                return .none

            case let .mcpServerEvent(event):
                let debugEffect = Effect<Action>.send(.debugPanel(.eventReceived(event)))
                switch event {
                case let .errorOccurred(message):
                    return .merge(
                        .send(.statusBar(.errorReported(source: .mcpServer, message: message))),
                        debugEffect
                    )
                case let .progressReported(worktreeId, _, statusText):
                    return .merge(
                        .send(.worktree(.claudeStatusTextChanged(
                            worktreeId: worktreeId,
                            text: statusText
                        ))),
                        debugEffect
                    )
                case let .activityReported(worktreeId, text):
                    return .merge(
                        .send(.worktree(.claudeActivityTextChanged(
                            worktreeId: worktreeId,
                            text: text
                        ))),
                        debugEffect
                    )
                case let .meisterHelloReceived(worktreeId):
                    return .merge(
                        .send(.worktree(.meisterHelloReceived(worktreeId: worktreeId))),
                        debugEffect
                    )
                case let .meisterConnectionClosed(worktreeId):
                    return .merge(
                        .send(.worktree(.meisterConnectionClosed(worktreeId: worktreeId))),
                        debugEffect
                    )
                case let .itemMovedToProcessing(worktreeId, issueLinearId):
                    return .merge(
                        .send(.worktree(.mcpItemMovedToProcessing(
                            worktreeId: worktreeId, issueLinearId: issueLinearId
                        ))),
                        debugEffect
                    )
                case let .itemMovedToOutbox(worktreeId, issueLinearId):
                    return .merge(
                        .send(.worktree(.mcpItemMovedToOutbox(
                            worktreeId: worktreeId, issueLinearId: issueLinearId
                        ))),
                        debugEffect
                    )
                case let .itemAddedToInbox(worktreeId, issueLinearId):
                    return .merge(
                        .send(.worktree(.mcpItemAddedToInbox(
                            worktreeId: worktreeId, issueLinearId: issueLinearId
                        ))),
                        debugEffect
                    )
                case let .itemRemovedFromInbox(worktreeId, issueLinearId):
                    return .merge(
                        .send(.worktree(.mcpItemRemovedFromInbox(
                            worktreeId: worktreeId, issueLinearId: issueLinearId
                        ))),
                        debugEffect
                    )
                case .scheduleSaved, .scheduleDeleted, .scheduleRun:
                    // Refetch all repos — none of these payloads carry repoId.
                    return .merge(
                        .send(.worktree(.refreshSchedulesRequested)),
                        debugEffect
                    )
                case let .scheduleItemStatusChanged(scheduleItemId, status):
                    return .merge(
                        .send(.worktree(.mcpScheduleItemStatusChanged(
                            scheduleItemId: scheduleItemId, status: status
                        ))),
                        debugEffect
                    )
                }
            }
        }
    }

    // Routes a command palette selection to the appropriate child action.
    // swiftlint:disable:next cyclomatic_complexity
    private func executeCommand(
        _ command: AppCommand,
        state: inout State
    ) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            return .send(.toggleSidebar)
        case .toggleInspector:
            return .send(.toggleInspector)
        case .showMeister:
            state.showMeister = true
            state.worktree.selectedWorktreeId = nil
            return .none
        case .showWorktrees:
            state.showMeister = false
            return .none
        case .openCommandPalette:
            return .none
        case .syncLinearIssues:
            return .send(.meister(.refreshTapped))
        case .openLinearAuth:
            return .send(.linearAuth(.loginButtonTapped))
        case .openTeamSettings:
            state.teamSettings = TeamSettingsFeature.State()
            return .none
        case .newWorktree:
            return .send(.worktree(.createSheetShown(prefilledRepoId: nil)))
        case .toggleDebugPanel:
            return .send(.debugPanel(.panelToggled))
        case .openShortcutCenter:
            return .send(.openShortcutCenter)
        case .openWorktreeSwitcher:
            return .send(.openWorktreeSwitcher)
        case .deleteWorktree:
            guard let worktreeId = state.worktree.selectedWorktreeId else { return .none }
            return .send(.worktree(.confirmDeleteTapped(worktreeId: worktreeId)))
        case .markIssueDone:
            guard let worktreeId = state.worktree.selectedWorktreeId else { return .none }
            return .send(.worktree(.markAsCompleteTapped(worktreeId: worktreeId)))
        case .returnIssueToMeister, .removeIssue:
            // Contextual — handled directly by context menu closures
            return .none
        }
    }
}
