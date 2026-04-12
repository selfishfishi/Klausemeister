import ComposableArchitecture
import SwiftUI

struct MeisterTabView: View {
    let meisterStore: StoreOf<MeisterFeature>
    let worktreeStore: StoreOf<WorktreeFeature>
    let authStore: StoreOf<LinearAuthFeature>
    let onConnect: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Group {
            switch authStore.status {
            case .authenticated:
                VSplitView {
                    MeisterView(
                        store: meisterStore,
                        worktrees: Array(worktreeStore.worktrees),
                        repositories: Array(worktreeStore.repositories),
                        assignedWorktreeNames: worktreeStore.assignedWorktreeNames,
                        teams: meisterStore.teams
                    )
                    .frame(minHeight: 200)
                    WorktreeSwimlaneView(
                        store: worktreeStore,
                        teams: meisterStore.teams
                    )
                    .frame(minHeight: 150)
                }
            case .teamSelection:
                TeamPickerView(
                    teams: authStore.availableTeams,
                    selectedTeamIds: authStore.selectedTeamIds,
                    onToggle: { id in authStore.send(.teamToggled(id: id)) },
                    onConfirm: { authStore.send(.teamSelectionConfirmed) }
                )
            case .unauthenticated, .authenticating, .fetchingTeams:
                LinearConnectView(status: authStore.status, onConnect: onConnect)
            }
        }
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
        .tint(themeColors.accentColor)
    }
}
