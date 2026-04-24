import ComposableArchitecture
import SwiftUI

struct TerminalContainerView: View {
    @Bindable var store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    @Environment(\.themeColors) private var themeColors
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didSeedInspectorPref = false
    @State private var didPrimeInitialTheme = false
    @AppStorage("inspectorOpen") private var inspectorOpenPref: Bool = false
    @AppStorage(AppTheme.storageKey) private var selectedTheme: AppTheme = .everforestDarkMedium

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
                DetailPane(store: store, surfaceStore: surfaceStore)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(store: store.scope(state: \.statusBar, action: \.statusBar))
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                InspectorOverlay(store: store)
            }
            .navigationSplitViewStyle(.balanced)

            CommandPaletteOverlay(store: store)
            WorktreeSwitcherOverlay(store: store)
            ScheduleGanttOverlay(store: store)
        }
        // Cross-cutting animations and lifecycle modifiers stay on the
        // parent. They read specific keypaths (showInspector,
        // commandPalette?, worktreeSwitcher?) which causes the parent's
        // body to re-run on those transitions — cheap, because the
        // expensive subtrees above are already isolated in their own
        // Equatable child views whose `body` is skipped when their
        // `store` reference is unchanged.
        .animation(.easeInOut(duration: 0.2), value: store.showInspector)
        .animation(
            .spring(duration: 0.2, bounce: 0.1),
            value: store.commandPalette != nil
                || store.worktreeSwitcher != nil
                || store.presentedScheduleId != nil
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
            inspectorOpenPref = newValue
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(themeColors.accentColor)
        .environment(\.keyBindings, store.keyBindings)
        .task {
            // Seed TCA state from @AppStorage on first appearance. Guarded by a
            // separate flag so repeated .task firings don't loop against the
            // `.onChange` above (which would overwrite the persisted value if
            // `showInspector` was toggled before `.task` ran).
            if !didSeedInspectorPref {
                didSeedInspectorPref = true
                if inspectorOpenPref != store.showInspector {
                    store.send(.toggleInspector)
                }
            }
            if !didPrimeInitialTheme {
                didPrimeInitialTheme = true
                store.send(.initialThemeSeeded(selectedTheme))
            }
            store.send(.onAppear)
        }
        .sheet(
            item: $store.scope(state: \.shortcutCenter, action: \.shortcutCenter)
        ) { scStore in
            ShortcutCenterView(store: scStore)
        }
        .sheet(
            item: $store.scope(state: \.teamSettings, action: \.teamSettings)
        ) { settingsStore in
            TeamSettingsView(store: settingsStore)
        }
    }
}

// MARK: - Detail pane

/// Switches between Meister and WorktreeDetail. Reads only `showMeister`,
/// `meister.teams`, and the `worktree` scope — other app-level state changes
/// (inspector, palette, sheets) don't trigger a rebuild of either subtree.
private struct DetailPane: View {
    let store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    var body: some View {
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
                teamsByID: store.meister.teamsByID
            )
        }
    }
}

// MARK: - Inspector overlay

/// Renders the inspector pane when `showInspector` is true. Isolated so
/// `inspectorDetail` changes (typically a ticket fetch result) only
/// rebuild this view, not the whole window.
private struct InspectorOverlay: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if store.showInspector {
            TicketInspectorView(
                state: store.inspectorDetail,
                onRetry: {
                    if case let .ticket(id) = store.inspectorSelection {
                        store.send(.inspectorSelectionRequested(issueId: id))
                    }
                },
                onClose: { store.send(.toggleInspector) }
            )
            .frame(width: 320)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

// MARK: - Command palette overlay

/// Scrim + command palette, conditional on `commandPalette` presence. The
/// `@Bindable` scope is read only here, so keystrokes inside the palette
/// don't re-render the detail pane or sidebar.
private struct CommandPaletteOverlay: View {
    let store: StoreOf<AppFeature>

    var body: some View {
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
}

// MARK: - Worktree switcher overlay

/// Scrim + worktree switcher, isolated for the same reason as the palette.
private struct WorktreeSwitcherOverlay: View {
    let store: StoreOf<AppFeature>

    var body: some View {
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
}

// MARK: - Schedule gantt overlay

/// Scrim + gantt overlay, conditional on `presentedScheduleId` being set.
/// Resolves the full `Schedule` from `worktree.schedulesByRepoId` and the
/// matching repo's worktrees in display order. Outside-tap and Escape both
/// dismiss via `.ganttOverlayDismissed`.
private struct ScheduleGanttOverlay: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let scheduleId = store.presentedScheduleId,
           let schedule = findSchedule(id: scheduleId, in: store.worktree.schedulesByRepoId)
        {
            let worktrees = store.worktree.worktrees
                .filter { $0.repoId == schedule.repoId }
                .sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder {
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    return lhs.name < rhs.name
                }

            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { store.send(.ganttOverlayDismissed) }

            ScheduleGanttView(
                schedule: schedule,
                worktrees: worktrees,
                isRunInFlight: store.worktree.scheduleRunInFlight.contains(scheduleId),
                onRunTapped: { store.send(.ganttRunTapped(scheduleId: scheduleId)) },
                onFinishTapped: { store.send(.ganttFinishTapped(scheduleId: scheduleId)) },
                onClose: { store.send(.ganttOverlayDismissed) }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .zIndex(2)
            .onKeyPress(.escape) {
                store.send(.ganttOverlayDismissed)
                return .handled
            }
        }
    }

    private func findSchedule(
        id: String,
        in schedulesByRepoId: [String: [Schedule]]
    ) -> Schedule? {
        for (_, schedules) in schedulesByRepoId {
            if let match = schedules.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }
}
