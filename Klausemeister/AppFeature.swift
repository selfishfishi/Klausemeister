import ComposableArchitecture
import Foundation

@Reducer
// swiftlint:disable:next type_body_length
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var showSidebar: Bool = true
        var showMeister: Bool = true
        var meister = MeisterFeature.State()
        var worktree = WorktreeFeature.State()
        var linearAuth = LinearAuthFeature.State()
        var statusBar = StatusBarFeature.State()
        var debugPanel = DebugPanelFeature.State()
        var teamSettings: TeamSettingsFeature.State?
        var commandPalette: CommandPaletteFeature.State?
        var shortcutCenter: ShortcutCenterFeature.State?
        var worktreeSwitcher: WorktreeSwitcherFeature.State?
        var keyBindings: [AppCommand: KeyBinding] = [:]
    }

    enum Action {
        case onAppear
        case toggleSidebar
        case themeChanged(AppTheme)
        case oauthCallbackReceived(URL)
        case showMeister
        case meister(MeisterFeature.Action)
        case worktree(WorktreeFeature.Action)
        case linearAuth(LinearAuthFeature.Action)
        case statusBar(StatusBarFeature.Action)
        case debugPanel(DebugPanelFeature.Action)
        case teamSettingsButtonTapped
        case teamSettingsDismissed
        case teamSettings(TeamSettingsFeature.Action)
        case openCommandPalette
        case commandPalette(CommandPaletteFeature.Action)
        case openShortcutCenter
        case shortcutCenterDismissed
        case shortcutCenter(ShortcutCenterFeature.Action)
        case openWorktreeSwitcher
        case worktreeSwitcher(WorktreeSwitcherFeature.Action)
        case selectWorktreeByPosition(Int)
        case keyBindingsLoaded([AppCommand: KeyBinding?])
        case mcpServerEvent(MCPServerEvent)
    }

    nonisolated private enum CancelID {
        case mcpServer
    }

    @Dependency(\.actionRegistry) var actionRegistry
    @Dependency(\.keyBindingsClient) var keyBindingsClient
    @Dependency(\.surfaceManager) var surfaceManager
    @Dependency(\.ghosttyApp) var ghosttyApp
    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.mcpServerClient) var mcpServerClient

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
        .ifLet(\.teamSettings, action: \.teamSettings) {
            TeamSettingsFeature()
        }
        .ifLet(\.commandPalette, action: \.commandPalette) {
            CommandPaletteFeature()
        }
        .ifLet(\.shortcutCenter, action: \.shortcutCenter) {
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
                    .run { [keyBindingsClient] send in
                        let overrides = await (try? keyBindingsClient.loadOverrides()) ?? [:]
                        await send(.keyBindingsLoaded(overrides))
                    },
                    .run { [mcpServerClient] _ in
                        await mcpServerClient.start()
                    }
                    .cancellable(id: CancelID.mcpServer),
                    .run { [mcpServerClient] send in
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

            case .worktree:
                return .none

            case .toggleSidebar:
                state.showSidebar.toggle()
                return .none

            case let .themeChanged(theme):
                return .run { _ in
                    await MainActor.run {
                        ghosttyApp.rebuild(theme)
                        surfaceManager.recreateAllSurfaces()
                    }
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

            case .shortcutCenterDismissed:
                state.shortcutCenter = nil
                return .none

            case let .shortcutCenter(.delegate(.bindingsSaved(newBindings))):
                state.shortcutCenter = nil
                state.keyBindings = newBindings
                return .none

            case .shortcutCenter(.delegate(.dismissed)):
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

            case .teamSettingsDismissed:
                state.teamSettings = nil
                return .none

            case let .teamSettings(.delegate(.teamsUpdated(teams))):
                state.teamSettings = nil
                return .merge(
                    .send(.meister(.teamsConfirmed(teams))),
                    .send(.worktree(.onAppear))
                )

            case .teamSettings(.delegate(.dismissed)):
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
                case .progressReported:
                    return debugEffect
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
            state.showSidebar.toggle()
            return .none
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
