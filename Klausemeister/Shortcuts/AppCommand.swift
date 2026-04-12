import Foundation

enum AppCommand: String, CaseIterable, Hashable {
    case toggleSidebar
    case showMeister
    case showWorktrees
    case openCommandPalette
    case syncLinearIssues
    case openLinearAuth
    case openTeamSettings
    case newWorktree
    case toggleDebugPanel

    enum Category: String, CaseIterable {
        case view
        case navigation
        case linear
        case worktree
        case system
    }

    var displayName: String {
        switch self {
        case .toggleSidebar: "Toggle Sidebar"
        case .showMeister: "Show Meister"
        case .showWorktrees: "Show Worktrees"
        case .openCommandPalette: "Open Command Palette"
        case .syncLinearIssues: "Sync Linear Issues"
        case .openLinearAuth: "Connect to Linear"
        case .openTeamSettings: "Team Settings"
        case .newWorktree: "New Worktree"
        case .toggleDebugPanel: "Toggle Debug Panel"
        }
    }

    var category: Category {
        switch self {
        case .toggleSidebar: .view
        case .showMeister, .showWorktrees, .openCommandPalette: .navigation
        case .syncLinearIssues, .openLinearAuth, .openTeamSettings: .linear
        case .newWorktree: .worktree
        case .toggleDebugPanel: .system
        }
    }

    var helpText: String {
        switch self {
        case .toggleSidebar: "Show or hide the sidebar"
        case .showMeister: "Switch to the Meister view"
        case .showWorktrees: "Switch to the Worktrees view"
        case .openCommandPalette: "Search and run any command"
        case .syncLinearIssues: "Pull latest issues from Linear"
        case .openLinearAuth: "Sign in or manage Linear connection"
        case .openTeamSettings: "Configure which Linear teams are shown"
        case .newWorktree: "Create a new git worktree"
        case .toggleDebugPanel: "Show or hide the MCP diagnostics panel"
        }
    }

    nonisolated var defaultBinding: KeyBinding? {
        switch self {
        case .toggleSidebar: KeyBinding(key: "\\", modifiers: .command)
        case .openCommandPalette: KeyBinding(key: "k", modifiers: .command)
        case .toggleDebugPanel: KeyBinding(key: "d", modifiers: [.command, .shift])
        case .showMeister, .showWorktrees, .syncLinearIssues,
             .openLinearAuth, .openTeamSettings, .newWorktree:
            nil
        }
    }
}
