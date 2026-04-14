import ComposableArchitecture
import SwiftUI

struct TerminalContainerView: View {
    let store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    @Environment(\.themeColors) private var themeColors
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("inspectorOpen") private var inspectorOpenPref: Bool = false

    private var inspectorViewState: TicketInspectorView.ViewState {
        switch store.inspectorDetail {
        case .empty: .empty
        case .loading: .loading
        case let .error(message): .error(message)
        case let .loaded(detail): .loaded(detail)
        }
    }

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
                        onConnect: { store.send(.linearAuth(.loginButtonTapped)) },
                        onManageTeams: { store.send(.teamSettingsButtonTapped) }
                    )
                } else {
                    WorktreeDetailView(
                        store: store.scope(state: \.worktree, action: \.worktree),
                        surfaceStore: surfaceStore,
                        teamsByID: store.meister.teams.count > 1
                            ? Dictionary(uniqueKeysWithValues: store.meister.teams.map { ($0.id, $0) })
                            : [:]
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(store: store.scope(state: \.statusBar, action: \.statusBar))
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if store.showInspector {
                    TicketInspectorView(
                        state: inspectorViewState,
                        onClose: { store.send(.toggleInspector) }
                    )
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.showInspector)
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

            if let switcherStore = store.scope(
                state: \.worktreeSwitcher, action: \.worktreeSwitcher
            ) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { switcherStore.send(.dismiss) }

                WorktreeSwitcherView(store: switcherStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 80)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(1)
            }
        }
        .animation(
            .spring(duration: 0.2, bounce: 0.1),
            value: store.commandPalette != nil || store.worktreeSwitcher != nil
        )
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
        .onChange(of: store.showInspector) { _, newValue in
            if inspectorOpenPref != newValue {
                inspectorOpenPref = newValue
            }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(themeColors.accentColor)
        .environment(\.keyBindings, store.keyBindings)
        .task {
            if inspectorOpenPref != store.showInspector {
                store.send(.toggleInspector)
            }
            store.send(.onAppear)
        }
        .sheet(
            isPresented: Binding(
                get: { store.shortcutCenter != nil },
                set: { if !$0 { store.send(.shortcutCenterDismissed) } }
            )
        ) {
            if let scStore = store.scope(
                state: \.shortcutCenter, action: \.shortcutCenter
            ) {
                ShortcutCenterView(store: scStore)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.teamSettings != nil },
                set: { if !$0 { store.send(.teamSettingsDismissed) } }
            )
        ) {
            if let settingsStore = store.scope(
                state: \.teamSettings, action: \.teamSettings
            ) {
                TeamSettingsView(store: settingsStore)
            }
        }
    }
}
