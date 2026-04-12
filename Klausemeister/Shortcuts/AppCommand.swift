import Foundation

enum AppCommand: String, CaseIterable, Hashable {
    case toggleSidebar
    case showMeister

    enum Category: String, CaseIterable {
        case view
        case navigation
    }

    var displayName: String {
        switch self {
        case .toggleSidebar: "Toggle Sidebar"
        case .showMeister: "Show Meister"
        }
    }

    var category: Category {
        switch self {
        case .toggleSidebar: .view
        case .showMeister: .navigation
        }
    }

    var helpText: String {
        switch self {
        case .toggleSidebar: "Show or hide the sidebar"
        case .showMeister: "Switch to the Meister view"
        }
    }

    nonisolated var defaultBinding: KeyBinding? {
        switch self {
        case .toggleSidebar: KeyBinding(key: "\\", modifiers: .command)
        case .showMeister: nil
        }
    }
}
