import Foundation

enum WorktreeConfig {
    nonisolated static let defaultBasePath = ".worktrees"
    nonisolated static let userDefaultsBasePathKey = "worktreeBasePath"

    nonisolated static func branchName(fromIdentifier identifier: String) -> String {
        identifier.lowercased()
    }

    nonisolated static func worktreePath(basePath: String, repoRoot: String, name: String) -> String {
        if basePath.hasPrefix("/") {
            return "\(basePath)/\(name.lowercased())"
        }
        return "\(repoRoot)/\(basePath)/\(name.lowercased())"
    }
}
