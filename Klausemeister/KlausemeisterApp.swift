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
        }
    }

    var body: some Scene {
        WindowGroup {
            TerminalContainerView(store: store, surfaceStore: surfaceStore)
                .onOpenURL { url in
                    store.send(.oauthCallbackReceived(url))
                }
        }
        .defaultSize(width: 900, height: 600)
        .environment(\.themeColors, selectedTheme.colors)
        .onChange(of: selectedTheme) { _, newTheme in
            store.send(.themeChanged(newTheme))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    store.send(.newTabButtonTapped)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let id = store.activeTabID {
                        store.send(.closeTabButtonTapped(id))
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Show Previous Tab") {
                    store.send(.previousTabShortcutPressed)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Show Next Tab") {
                    store.send(.nextTabShortcutPressed)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Sidebar") {
                    store.send(.sidebarTogglePressed)
                }
                .keyboardShortcut("\\", modifiers: .command)
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

            CommandMenu("Tabs") {
                // swiftlint:disable:next identifier_name
                ForEach(1 ... 9, id: \.self) { i in
                    Button("Tab \(i)") {
                        store.send(.tabShortcutPressed(position: i))
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
            }
        }
    }
}
