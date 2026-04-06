import ComposableArchitecture
import SwiftUI

struct MeisterTabView: View {
    let meisterStore: StoreOf<MeisterFeature>
    let worktreeStore: StoreOf<WorktreeFeature>
    let authStatus: LinearAuthFeature.AuthStatus
    let onConnect: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Group {
            if authStatus == .authenticated {
                VSplitView {
                    MeisterView(
                        store: meisterStore,
                        worktrees: Array(worktreeStore.worktrees),
                        repositories: Array(worktreeStore.repositories),
                        assignedWorktreeNames: worktreeStore.assignedWorktreeNames
                    )
                    .frame(minHeight: 200)
                    WorktreeSwimlaneView(store: worktreeStore)
                        .frame(minHeight: 150)
                }
            } else {
                LinearConnectView(status: authStatus, onConnect: onConnect)
            }
        }
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
        .tint(themeColors.accentColor)
    }
}
