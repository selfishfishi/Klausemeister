import ComposableArchitecture
import SwiftUI

@main
struct KlausemeisterApp: App {
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .everforestDarkMedium

    let surfaceStore: SurfaceStore
    let store: StoreOf<AppFeature>

    init() {
        let surfaceStore = SurfaceStore()
        self.surfaceStore = surfaceStore

        // Rewrite any legacy `selectedTheme` value to the current raw so
        // `@AppStorage` and future reads match the new theme families.
        // The actual initial `ghostty` rebuild is primed by
        // `TerminalContainerView.task` via `.initialThemeSeeded(_:)`, which
        // goes through `@Dependency(\.ghosttyApp)` instead of the singleton.
        let resolved = AppTheme.resolve(
            stored: UserDefaults.standard.string(forKey: "selectedTheme")
        )
        UserDefaults.standard.set(resolved.rawValue, forKey: "selectedTheme")

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
                .handlesExternalEvents(
                    preferring: ["klausemeister"],
                    allowing: ["klausemeister"]
                )
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
        .handlesExternalEvents(matching: ["klausemeister"])
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

                Button(AppCommand.toggleInspector.displayName) {
                    store.send(.toggleInspector)
                }
                .keyboardShortcut(for: .toggleInspector, in: bindings)

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

                Button(AppCommand.openWorktreeSwitcher.displayName) {
                    store.send(.openWorktreeSwitcher)
                }
                .keyboardShortcut(for: .openWorktreeSwitcher, in: bindings)
            }

            CommandGroup(after: .appSettings) {
                Button(AppCommand.openShortcutCenter.displayName) {
                    store.send(.openShortcutCenter)
                }
                .keyboardShortcut(for: .openShortcutCenter, in: store.keyBindings)
            }

            CommandMenu("Worktrees") {
                ForEach(1 ... 9, id: \.self) { position in
                    Button("Worktree \(position)") {
                        store.send(.selectWorktreeByPosition(position))
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(position))),
                        modifiers: .command
                    )
                }
            }

            CommandMenu("Debug") {
                Button(AppCommand.toggleDebugPanel.displayName) {
                    store.send(.debugPanel(.panelToggled))
                }
                .keyboardShortcut(for: .toggleDebugPanel, in: store.keyBindings)
            }
            CommandMenu("Theme") {
                ForEach(ThemeFamily.allCases) { family in
                    Section(family.displayName) {
                        ForEach(family.darkVariants + family.lightVariants) { theme in
                            Button {
                                selectedTheme = theme
                            } label: {
                                if theme == selectedTheme {
                                    Label(theme.variantName, systemImage: "checkmark")
                                } else {
                                    Text(theme.variantName)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
