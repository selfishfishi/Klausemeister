import ComposableArchitecture
import SwiftUI

struct TerminalContainerView: View {
    let store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    @Environment(\.themeColors) private var themeColors
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                    .background {
                        ZStack {
                            Color(hexString: themeColors.background)
                            themeColors.accentColor.opacity(0.04)
                        }
                        .ignoresSafeArea()
                    }
                    .scrollContentBackground(.hidden)
            } detail: {
                if store.showMeister {
                    MeisterTabView(
                        meisterStore: store.scope(state: \.meister, action: \.meister),
                        worktreeStore: store.scope(state: \.worktree, action: \.worktree),
                        authStore: store.scope(state: \.linearAuth, action: \.linearAuth),
                        onConnect: { store.send(.linearAuth(.loginButtonTapped)) }
                    )
                } else {
                    WorktreeDetailView(
                        store: store.scope(state: \.worktree, action: \.worktree),
                        surfaceStore: surfaceStore,
                        teams: store.meister.teams
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(store: store.scope(state: \.statusBar, action: \.statusBar))
            }
            .navigationSplitViewStyle(.balanced)

            if let paletteStore = store.scope(
                state: \.commandPalette, action: \.commandPalette
            ) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { paletteStore.send(.dismiss) }

                CommandPaletteView(store: paletteStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 80)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0.1), value: store.commandPalette != nil)
        .onChange(of: store.showSidebar) { _, show in
            withAnimation {
                columnVisibility = show ? .all : .detailOnly
            }
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            let shouldShow = (newVisibility != .detailOnly)
            if shouldShow != store.showSidebar {
                store.send(.toggleSidebar)
            }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(themeColors.accentColor)
        .task { store.send(.onAppear) }
    }
}
