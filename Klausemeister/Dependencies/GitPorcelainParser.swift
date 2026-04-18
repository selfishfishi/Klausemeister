// Klausemeister/Dependencies/GitPorcelainParser.swift
import Foundation

/// Parses the `git worktree list --porcelain` output into
/// `GitClient.WorktreeListEntry` values. Extracted from `GitClient.swift`
/// to keep that file under the 500-line limit; the logic is pure and has
/// no dependencies other than `GitClient`'s nested types.
nonisolated func parseWorktreeListPorcelain(_ output: String) -> [GitClient.WorktreeListEntry] {
    var entries: [GitClient.WorktreeListEntry] = []
    let blocks = output.components(separatedBy: "\n\n")
    var isFirst = true
    for block in blocks {
        let lines = block.split(separator: "\n").map(String.init)
        var path: String?
        var branch: String?
        var isLocked = false
        var isPrunable = false
        for line in lines {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            } else if line == "locked" || line.hasPrefix("locked ") {
                isLocked = true
            } else if line == "prunable" || line.hasPrefix("prunable ") {
                isPrunable = true
            }
        }
        if let path {
            entries.append(GitClient.WorktreeListEntry(
                path: path,
                branch: branch,
                isMain: isFirst,
                isLocked: isLocked,
                isPrunable: isPrunable
            ))
            isFirst = false
        }
    }
    return entries
}
