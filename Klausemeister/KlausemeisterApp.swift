import SwiftUI

@main
struct KlausemeisterApp: App {
    @State private var windowState = WindowState()

    var body: some Scene {
        WindowGroup {
            TerminalContainerView(windowState: windowState)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    windowState.createTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let id = windowState.activeTabID {
                        windowState.closeTab(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Show Previous Tab") {
                    windowState.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Show Next Tab") {
                    windowState.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Sidebar") {
                    windowState.showSidebar.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }

            CommandMenu("Tabs") {
                ForEach(1...9, id: \.self) { i in
                    Button("Tab \(i)") {
                        windowState.selectTab(at: i)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
            }
        }
    }
}
