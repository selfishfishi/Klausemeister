import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var showSidebar: Bool = true
        var showMeister: Bool = true
        var meister = MeisterFeature.State()
        var worktree = WorktreeFeature.State()
        var linearAuth = LinearAuthFeature.State()
        var statusBar = StatusBarFeature.State()
    }

    enum Action {
        case onAppear
        case sidebarTogglePressed
        case themeChanged(AppTheme)
        case oauthCallbackReceived(URL)
        case meisterTapped
        case meister(MeisterFeature.Action)
        case worktree(WorktreeFeature.Action)
        case linearAuth(LinearAuthFeature.Action)
        case statusBar(StatusBarFeature.Action)
        case mcpServerEvent(MCPServerEvent)
    }

    nonisolated private enum CancelID {
        case mcpServer
    }

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
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
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

            case .meisterTapped:
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

            case .sidebarTogglePressed:
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

            case .statusBar:
                return .none

            case let .mcpServerEvent(.errorOccurred(message)):
                return .send(.statusBar(.errorReported(source: .mcpServer, message: message)))

            case .mcpServerEvent(.progressReported):
                // KLA-80 will route per-session progress into the sidebar.
                // For v1, we accept the event and surface nothing — the
                // meister sees its own status, and errors take a different path.
                return .none

            case let .mcpServerEvent(.meisterHelloReceived(worktreeId)):
                return .send(.worktree(.meisterHelloReceived(worktreeId: worktreeId)))

            case let .mcpServerEvent(.meisterConnectionClosed(worktreeId)):
                return .send(.worktree(.meisterConnectionClosed(worktreeId: worktreeId)))
            }
        }
    }
}
