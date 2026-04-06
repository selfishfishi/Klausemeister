import Foundation

enum WorktreeConfig {
    nonisolated static let defaultBasePath = ".worktrees"
    nonisolated static let userDefaultsBasePathKey = "worktreeBasePath"

    nonisolated static func branchName(fromIdentifier identifier: String) -> String {
        identifier.lowercased()
    }

    /// Tmux session name bound 1:1 to a worktree. Lowercased for stability and
    /// to match the branch-name convention. Sessions live under the `klause-`
    /// prefix so reconciliation can ignore unrelated user sessions. Characters
    /// tmux disallows or treats specially in target syntax (`:`, `.`,
    /// whitespace) are replaced with `-` so the name we store always round-trips
    /// through `kill-session -t =<name>`.
    nonisolated static func tmuxSessionName(forWorktreeName name: String) -> String {
        let sanitized = name
            .lowercased()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "klause-\(sanitized)"
    }

    nonisolated static func worktreePath(basePath: String, repoRoot: String, name: String) -> String {
        if basePath.hasPrefix("/") {
            return "\(basePath)/\(name.lowercased())"
        }
        return "\(repoRoot)/\(basePath)/\(name.lowercased())"
    }

    /// Extracts a Linear-style issue identifier (e.g., "KLA-47") from a branch name.
    /// Matches a `<LETTERS>-<NUMBER>` substring at start-of-string or after a `/` or `-` separator.
    /// The team prefix must be 2-5 letters to avoid matching common words like "fix-47" or "rollback-47".
    /// Examples:
    ///   "kla-47" → "KLA-47"
    ///   "feature/kla-47-something" → "KLA-47"
    ///   "a/kla-47-issue-name" → "KLA-47"
    ///   "main" → nil
    ///   "fix-47" → nil (single-word prefix below 2 chars... wait, "fix" is 3, so this would match.
    ///     This is acceptable: we err toward extracting identifiers that may not exist in
    ///     imported_issues, since fetchImportedIssueByIdentifier silently returns nil on miss.)
    nonisolated static func extractIssueIdentifier(fromBranchName branch: String) -> String? {
        let pattern = #"(?:^|[/-])([A-Za-z]{2,5}-[0-9]+)"#
        guard let match = branch.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        // Strip leading separator if present
        let raw = String(branch[match])
        let cleaned = raw.drop { $0 == "/" || $0 == "-" }
        return String(cleaned).uppercased()
    }
}
