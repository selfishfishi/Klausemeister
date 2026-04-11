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
        }
        .defaultSize(width: 900, height: 600)
        .environment(\.themeColors, selectedTheme.colors)
        .onChange(of: selectedTheme) { _, newTheme in
            store.send(.themeChanged(newTheme))
        }
        .commands {
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
