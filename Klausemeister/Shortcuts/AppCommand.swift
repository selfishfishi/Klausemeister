import Foundation

enum AppCommand: String, CaseIterable, Hashable {
    // App-level commands
    case toggleSidebar
    case showMeister
    case showWorktrees
    case openCommandPalette
    case syncLinearIssues
    case openLinearAuth
    case openTeamSettings
    case newWorktree
    case toggleDebugPanel
    case openShortcutCenter

    // Contextual commands (operate on the selected/focused item)
    case deleteWorktree
    case markIssueDone
    case returnIssueToMeister
    case removeIssue

    enum Category: String, CaseIterable {
        case view
        case navigation
        case linear
        case worktree
        case issue
        case system
    }

    nonisolated var displayName: String {
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
        case .openShortcutCenter: "Keyboard Shortcuts"
        case .deleteWorktree: "Delete Worktree"
        case .markIssueDone: "Mark as Done"
        case .returnIssueToMeister: "Return to Meister"
        case .removeIssue: "Remove Issue"
        }
    }

    nonisolated var category: Category {
        switch self {
        case .toggleSidebar: .view
        case .showMeister, .showWorktrees, .openCommandPalette: .navigation
        case .syncLinearIssues, .openLinearAuth, .openTeamSettings: .linear
        case .newWorktree, .deleteWorktree: .worktree
        case .markIssueDone, .returnIssueToMeister, .removeIssue: .issue
        case .toggleDebugPanel, .openShortcutCenter: .system
        }
    }

    nonisolated var helpText: String {
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
        case .openShortcutCenter: "View and customize keyboard shortcuts"
        case .deleteWorktree: "Delete the selected worktree"
        case .markIssueDone: "Mark the active issue as done"
        case .returnIssueToMeister: "Return the issue to the kanban board"
        case .removeIssue: "Remove issue from the kanban board"
        }
    }

    nonisolated var defaultBinding: KeyBinding? {
        switch self {
        case .toggleSidebar: KeyBinding(key: "\\", modifiers: .command)
        case .openCommandPalette: KeyBinding(key: "k", modifiers: .command)
        case .toggleDebugPanel: KeyBinding(key: "d", modifiers: [.command, .shift])
        case .showMeister, .showWorktrees, .syncLinearIssues,
             .openLinearAuth, .openTeamSettings, .newWorktree,
             .openShortcutCenter, .deleteWorktree, .markIssueDone,
             .returnIssueToMeister, .removeIssue:
            nil
        }
    }
}
