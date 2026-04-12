import Dependencies
import Foundation
import OSLog

struct GitClient {
    var repositoryRoot: @Sendable (_ fromPath: String) async throws -> String
    var currentBranch: @Sendable (_ worktreePath: String) async throws -> String
    var addWorktree: @Sendable (
        _ repoPath: String,
        _ worktreePath: String,
        _ branch: String,
        _ baseRef: String?
    ) async throws -> Void
    var removeWorktree: @Sendable (_ repoPath: String, _ worktreePath: String) async throws -> Void
    var switchBranch: @Sendable (_ worktreePath: String, _ branchName: String) async throws -> Void
    var listWorktrees: @Sendable (_ repoPath: String) async throws -> [WorktreeListEntry]
    var listBranches: @Sendable (_ repoPath: String) async throws -> [String]
    var resolveDefaultBranch: @Sendable (_ repoPath: String) async throws -> DefaultBranch
    var fetchBranch: @Sendable (_ repoPath: String, _ branch: String) async throws -> Void
    var diffStats: @Sendable (_ worktreePath: String) async throws -> DiffStats
    var commitsAhead: @Sendable (_ worktreePath: String, _ defaultBranch: String) async throws -> Int
    /// Watches the git directory for a worktree and yields a value whenever
    /// the index, HEAD, or refs change. The caller should debounce.
    var watchForChanges: @Sendable (_ worktreePath: String) -> AsyncStream<Void>

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

    struct DiffStats: Equatable {
        let uncommittedFiles: Int
        let additions: Int
        let deletions: Int
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
                if let baseRef {
                    _ = try shell([
                        "-C", repoPath, "worktree", "add", worktreePath, "-b", branch, baseRef
                    ])
                } else {
                    _ = try shell([
                        "-C", repoPath, "worktree", "add", worktreePath, branch
                    ])
                }
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
            },
            diffStats: { worktreePath in
                // Count uncommitted files (staged + unstaged)
                let statusOutput = try shell([
                    "-C", worktreePath, "status", "--porcelain"
                ])
                let uncommitted = statusOutput
                    .split(separator: "\n", omittingEmptySubsequences: true).count

                // Additions/deletions vs HEAD (staged + unstaged combined).
                // In a fresh repo with no commits, HEAD doesn't exist and
                // `git diff HEAD` fails — fall back to `git diff --cached`.
                let numstat: String = if let headDiff = try? shell([
                    "-C", worktreePath, "diff", "HEAD", "--numstat"
                ]) {
                    headDiff
                } else {
                    (try? shell([
                        "-C", worktreePath, "diff", "--cached", "--numstat"
                    ])) ?? ""
                }
                var adds = 0
                var dels = 0
                for line in numstat.split(separator: "\n") {
                    let parts = line.split(separator: "\t")
                    guard parts.count >= 2 else { continue }
                    adds += Int(parts[0]) ?? 0
                    dels += Int(parts[1]) ?? 0
                }
                return GitClient.DiffStats(
                    uncommittedFiles: uncommitted,
                    additions: adds,
                    deletions: dels
                )
            },
            commitsAhead: { worktreePath, defaultBranch in
                let output = try shell([
                    "-C", worktreePath, "rev-list", "--count",
                    "\(defaultBranch)..HEAD"
                ])
                return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            },
            watchForChanges: { worktreePath in
                let log = Logger(subsystem: "com.klausemeister", category: "GitClient.watch")

                return AsyncStream { continuation in
                    // Resolve the git directory. For worktrees, .git is a file
                    // containing "gitdir: /path/to/main/.git/worktrees/<name>".
                    let dotGit = URL(fileURLWithPath: worktreePath)
                        .appendingPathComponent(".git")
                    let gitDirPath: String
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir),
                       !isDir.boolValue
                    {
                        if let content = try? String(contentsOf: dotGit, encoding: .utf8),
                           content.hasPrefix("gitdir: ")
                        {
                            gitDirPath = content
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "gitdir: ", with: "")
                        } else {
                            log.warning(
                                "watchForChanges: .git file at \(dotGit.path) is not a gitdir pointer; FS monitoring may miss events"
                            )
                            gitDirPath = dotGit.path
                        }
                    } else {
                        gitDirPath = dotGit.path
                    }

                    // Serial queue for debounce — all event handlers and
                    // debounce timers run here, eliminating data races.
                    let debounceQueue = DispatchQueue(
                        label: "com.klausemeister.git-watcher.\(worktreePath.hashValue)",
                        qos: .utility
                    )

                    // Open file descriptors for both the gitdir (catches file
                    // creation/deletion) and the index file (catches staging).
                    let dirFD = open(gitDirPath, O_EVTONLY)
                    let indexPath = (gitDirPath as NSString).appendingPathComponent("index")
                    let indexFD = open(indexPath, O_EVTONLY)

                    guard dirFD >= 0 || indexFD >= 0 else {
                        log.warning(
                            "watchForChanges: failed to open \(gitDirPath) (errno \(errno)); FS watcher inactive for \(worktreePath)"
                        )
                        continuation.finish()
                        return
                    }

                    // Shared debounce state — only accessed on debounceQueue.
                    var pendingWork: DispatchWorkItem?

                    func scheduleDebounce() {
                        pendingWork?.cancel()
                        let work = DispatchWorkItem { continuation.yield() }
                        pendingWork = work
                        debounceQueue.asyncAfter(
                            deadline: .now() + .seconds(2), execute: work
                        )
                    }

                    var sources: [DispatchSourceFileSystemObject] = []

                    if dirFD >= 0 {
                        let dirSource = DispatchSource.makeFileSystemObjectSource(
                            fileDescriptor: dirFD,
                            eventMask: [.write, .rename, .delete, .extend],
                            queue: debounceQueue
                        )
                        dirSource.setEventHandler { scheduleDebounce() }
                        dirSource.setCancelHandler { close(dirFD) }
                        sources.append(dirSource)
                    }

                    if indexFD >= 0 {
                        let indexSource = DispatchSource.makeFileSystemObjectSource(
                            fileDescriptor: indexFD,
                            eventMask: [.write, .rename, .delete],
                            queue: debounceQueue
                        )
                        indexSource.setEventHandler { scheduleDebounce() }
                        indexSource.setCancelHandler { close(indexFD) }
                        sources.append(indexSource)
                    }

                    let activeSources = sources
                    continuation.onTermination = { _ in
                        for source in activeSources {
                            source.cancel()
                        }
                    }

                    for source in activeSources {
                        source.resume()
                    }
                }
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
        fetchBranch: unimplemented("GitClient.fetchBranch"),
        diffStats: unimplemented("GitClient.diffStats"),
        commitsAhead: unimplemented("GitClient.commitsAhead"),
        watchForChanges: unimplemented(
            "GitClient.watchForChanges",
            placeholder: AsyncStream { $0.finish() }
        )
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
