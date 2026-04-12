import ComposableArchitecture
import SwiftUI

@main
struct KlausemeisterApp: App {
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .darkMedium

    let surfaceStore: SurfaceStore
    let store: StoreOf<AppFeature>

    init() {
        let surfaceStore = SurfaceStore()
        self.surfaceStore = surfaceStore

        let initialTheme = AppTheme(
            rawValue: UserDefaults.standard.string(forKey: "selectedTheme") ?? ""
        ) ?? .darkMedium
        GhosttyApp.shared.rebuild(theme: initialTheme)

        store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.surfaceManager = .live(
                surfaceStore: surfaceStore,
                ghosttyApp: $0.ghosttyApp
            )
            $0.meisterClient = .live(tmux: $0.tmuxClient)
        }
    }

    var body: some Scene {
        WindowGroup {
            TerminalContainerView(store: store, surfaceStore: surfaceStore)
                .onOpenURL { url in
                    store.send(.oauthCallbackReceived(url))
                }
                .preferredColorScheme(selectedTheme.isDark ? .dark : .light)
                .sheet(isPresented: Binding(
                    get: { store.debugPanel.showPanel },
                    set: { newValue in
                        if !newValue { store.send(.debugPanel(.panelToggled)) }
                    }
                )) {
                    DebugPanelView(
                        store: store.scope(state: \.debugPanel, action: \.debugPanel),
                        worktrees: Array(store.worktree.worktrees)
                    )
                }
        }
        .defaultSize(width: 900, height: 600)
        .environment(\.themeColors, selectedTheme.colors)
        .onChange(of: selectedTheme) { _, newTheme in
            store.send(.themeChanged(newTheme))
        }
        .commands {
            CommandGroup(after: .sidebar) {
                let bindings = store.keyBindings

                Button(AppCommand.toggleSidebar.displayName) {
                    store.send(.toggleSidebar)
                }
                .keyboardShortcut(for: .toggleSidebar, in: bindings)

                Button(AppCommand.openCommandPalette.displayName) {
                    store.send(.openCommandPalette)
                }
                .keyboardShortcut(for: .openCommandPalette, in: bindings)

                // VS Code compat shortcut (hidden from menu, shortcut still active)
                Button(AppCommand.openCommandPalette.displayName) {
                    store.send(.openCommandPalette)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .hidden()
            }

            CommandGroup(after: .appSettings) {
                Button(AppCommand.openShortcutCenter.displayName) {
                    store.send(.openShortcutCenter)
                }
                .keyboardShortcut(for: .openShortcutCenter, in: store.keyBindings)
            }

            CommandMenu("Debug") {
                Button(AppCommand.toggleDebugPanel.displayName) {
                    store.send(.debugPanel(.panelToggled))
                }
                .keyboardShortcut(for: .toggleDebugPanel, in: store.keyBindings)
            }
            CommandMenu("Theme") {
                Section("Dark") {
                    ForEach([AppTheme.darkHard, .darkMedium, .darkSoft]) { theme in
                        Button {
                            selectedTheme = theme
                        } label: {
                            if theme == selectedTheme {
                                Label(theme.displayName, systemImage: "checkmark")
                            } else {
                                Text(theme.displayName)
                            }
                        }
                    }
                }
                Section("Light") {
                    ForEach([AppTheme.lightHard, .lightMedium, .lightSoft]) { theme in
                        Button {
                            selectedTheme = theme
                        } label: {
                            if theme == selectedTheme {
                                Label(theme.displayName, systemImage: "checkmark")
                            } else {
                                Text(theme.displayName)
                            }
                        }
                    }
                }
            }
        }
    }
}
