import ComposableArchitecture
import SwiftUI

struct TerminalContainerView: View {
    let store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    @Environment(\.themeColors) private var themeColors
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if store.showMeister {
                MeisterView(store: store.scope(state: \.meister, action: \.meister))
            } else if store.worktree.selectedWorktreeId != nil {
                WorktreeDetailView(store: store.scope(state: \.worktree, action: \.worktree))
            } else {
                TerminalContentView(
                    surfaceView: store.activeTabID.flatMap { surfaceStore.surface(for: $0) },
                    activeTabID: store.activeTabID
                )
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .background {
                    Color(hexString: themeColors.background)
                        .ignoresSafeArea()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: store.showSidebar) { _, show in
            withAnimation {
                columnVisibility = show ? .all : .detailOnly
            }
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            let shouldShow = (newVisibility != .detailOnly)
            if shouldShow != store.showSidebar {
                store.send(.sidebarTogglePressed)
            }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(themeColors.accentColor)
        .task { store.send(.onAppear) }
    }
}
