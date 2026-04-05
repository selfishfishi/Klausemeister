import ComposableArchitecture
import SwiftUI

@main
struct KlausemeisterApp: App {
    let surfaceStore: SurfaceStore
    let store: StoreOf<AppFeature>

    init() {
        let surfaceStore = SurfaceStore()
        self.surfaceStore = surfaceStore
        self.store = Store(initialState: AppFeature.State()) {
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
        }
        .defaultSize(width: 900, height: 600)
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

            CommandMenu("Tabs") {
                ForEach(1...9, id: \.self) { i in
                    Button("Tab \(i)") {
                        store.send(.tabShortcutPressed(position: i))
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
            }
        }
    }
}
