import Foundation

enum AppCommand: String, CaseIterable, Hashable, Sendable {
    case toggleSidebar
    case showMeister

    enum Category: String, CaseIterable, Sendable {
        case view
        case navigation
    }

    var displayName: String {
        switch self {
        case .toggleSidebar: return "Toggle Sidebar"
        case .showMeister:   return "Show Meister"
        }
    }

    var category: Category {
        switch self {
        case .toggleSidebar: return .view
        case .showMeister:   return .navigation
        }
    }

    var helpText: String {
        switch self {
        case .toggleSidebar: return "Show or hide the sidebar"
        case .showMeister:   return "Switch to the Meister view"
        }
    }

    nonisolated var defaultBinding: KeyBinding? {
        switch self {
        case .toggleSidebar: return KeyBinding(key: "\\", modifiers: .command)
        case .showMeister:   return nil
        }
    }
}
