import Dependencies
import Foundation

struct GitClient {
    var repositoryRoot: @Sendable (_ fromPath: String) async throws -> String
    var currentBranch: @Sendable (_ worktreePath: String) async throws -> String
    var addWorktree: @Sendable (
        _ repoPath: String,
        _ worktreePath: String,
        _ branch: String,
        _ baseRef: String
    ) async throws -> Void
    var removeWorktree: @Sendable (_ repoPath: String, _ worktreePath: String) async throws -> Void
    var switchBranch: @Sendable (_ worktreePath: String, _ branchName: String) async throws -> Void
    var listWorktrees: @Sendable (_ repoPath: String) async throws -> [WorktreeListEntry]
    var listBranches: @Sendable (_ repoPath: String) async throws -> [String]
    var resolveDefaultBranch: @Sendable (_ repoPath: String) async throws -> DefaultBranch
    var fetchBranch: @Sendable (_ repoPath: String, _ branch: String) async throws -> Void

    struct WorktreeListEntry: Equatable {
        let path: String
        let branch: String?
        let isMain: Bool
        let isLocked: Bool
        let isPrunable: Bool
    }

    /// Result of resolving a repository's default branch. `hasOrigin` tells the
    /// caller whether to fetch from `origin` before creating a worktree and
    /// whether to base the new branch on `origin/<name>` or the local branch.
    struct DefaultBranch: Equatable {
        let name: String
        let hasOrigin: Bool
    }
}

enum GitClientError: Error, Equatable, LocalizedError {
    case notAGitRepository(String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .notAGitRepository(path):
            "Not a git repository: \(path)"
        case let .commandFailed(command, exitCode, stderr):
            "git \(command) failed (exit \(exitCode)): \(stderr)"
        }
    }
}

// MARK: - Live & Test values

extension GitClient: DependencyKey {
    nonisolated static let liveValue: GitClient = {
        @Sendable func shell(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let output = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                let cmd = arguments
                    .filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
                    .first ?? "git"
                throw GitClientError.commandFailed(
                    command: cmd,
                    exitCode: process.terminationStatus,
                    stderr: errorOutput
                )
            }
            return output
        }

        return GitClient(
            repositoryRoot: { fromPath in
                let result = try shell(["-C", fromPath, "rev-parse", "--show-toplevel"])
                guard !result.isEmpty else {
                    throw GitClientError.notAGitRepository(fromPath)
                }
                return result
            },
            currentBranch: { worktreePath in
                try shell(["-C", worktreePath, "rev-parse", "--abbrev-ref", "HEAD"])
            },
            addWorktree: { repoPath, worktreePath, branch, baseRef in
                _ = try shell([
                    "-C", repoPath, "worktree", "add", worktreePath, "-b", branch, baseRef
                ])
            },
            removeWorktree: { repoPath, worktreePath in
                _ = try shell(["-C", repoPath, "worktree", "remove", worktreePath, "--force"])
            },
            switchBranch: { worktreePath, branchName in
                _ = try shell(["-C", worktreePath, "checkout", "-B", branchName])
            },
            listWorktrees: { repoPath in
                let output = try shell(["-C", repoPath, "worktree", "list", "--porcelain"])
                return parseWorktreeListPorcelain(output)
            },
            listBranches: { repoPath in
                let output = try shell([
                    "-C", repoPath, "for-each-ref", "--format=%(refname:short)", "refs/heads/"
                ])
                return output
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            },
            resolveDefaultBranch: { repoPath in
                // Preferred path: origin/HEAD is set. Returns something like
                // "origin/main" — strip the remote prefix.
                if let symbolic = try? shell([
                    "-C", repoPath, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"
                ]), symbolic.hasPrefix("origin/") {
                    return GitClient.DefaultBranch(
                        name: String(symbolic.dropFirst("origin/".count)),
                        hasOrigin: true
                    )
                }
                // Fallback: no origin/HEAD set. Check for origin remote first.
                let remotes = (try? shell(["-C", repoPath, "remote"])) ?? ""
                let hasOrigin = remotes
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .contains("origin")
                // Pick whichever of main/master exists locally.
                for candidate in ["main", "master"]
                    where (try? shell([
                        "-C", repoPath, "rev-parse", "--verify", "--quiet", "refs/heads/\(candidate)"
                    ])) != nil
                {
                    return GitClient.DefaultBranch(name: candidate, hasOrigin: hasOrigin)
                }
                throw GitClientError.commandFailed(
                    command: "symbolic-ref",
                    exitCode: 1,
                    stderr: "Could not determine default branch: no origin/HEAD and neither main nor master exists locally."
                )
            },
            fetchBranch: { repoPath, branch in
                _ = try shell(["-C", repoPath, "fetch", "origin", branch])
            }
        )
    }()

    nonisolated static let testValue = GitClient(
        repositoryRoot: unimplemented("GitClient.repositoryRoot"),
        currentBranch: unimplemented("GitClient.currentBranch"),
        addWorktree: unimplemented("GitClient.addWorktree"),
        removeWorktree: unimplemented("GitClient.removeWorktree"),
        switchBranch: unimplemented("GitClient.switchBranch"),
        listWorktrees: unimplemented("GitClient.listWorktrees"),
        listBranches: unimplemented("GitClient.listBranches"),
        resolveDefaultBranch: unimplemented("GitClient.resolveDefaultBranch"),
        fetchBranch: unimplemented("GitClient.fetchBranch")
    )
}

// MARK: - Porcelain parser

nonisolated private func parseWorktreeListPorcelain(_ output: String) -> [GitClient.WorktreeListEntry] {
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

extension DependencyValues {
    var gitClient: GitClient {
        get { self[GitClient.self] }
        set { self[GitClient.self] = newValue }
    }
}
