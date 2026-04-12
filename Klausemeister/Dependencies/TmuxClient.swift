// Klausemeister/Dependencies/TmuxClient.swift
import Dependencies
import Foundation

struct TmuxClient {
    var createSession: @Sendable (
        _ name: String,
        _ workingDirectory: String,
        _ env: [String: String]
    ) async throws -> Void
    var sendKeys: @Sendable (_ target: String, _ keys: String) async throws -> Void
    var hasSession: @Sendable (_ name: String) async throws -> Bool
    var killSession: @Sendable (_ name: String) async throws -> Void
    var listSessions: @Sendable () async throws -> [String]
    /// Absolute path to the tmux binary probed at client construction, or
    /// nil if no known install location exists. Callers that hand tmux
    /// invocations to a PATH-stripped process (e.g. libghostty's
    /// `GHOSTTY_SURFACE_IO_BACKEND_EXEC` login shell, which runs the
    /// command under `/bin/bash --noprofile --norc`) must use this path
    /// instead of a bare `tmux` name.
    var resolvedTmuxPath: @Sendable () -> String?
}

enum TmuxClientError: Error, Equatable, LocalizedError {
    case tmuxNotFound
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .tmuxNotFound:
            "tmux not found. Install via `brew install tmux` and restart Klausemeister."
        case let .commandFailed(command, exitCode, stderr):
            "tmux \(command) failed (exit \(exitCode)): \(stderr)"
        }
    }
}

// MARK: - Live & Test values

extension TmuxClient: DependencyKey {
    nonisolated static let liveValue: TmuxClient = {
        // Probe known install locations once at construction time. Stored as a
        // captured local so every closure shares the same resolved (or unresolved)
        // path. Resolution is a `stat()` per candidate — fast, no I/O blocking.
        let tmuxPath: String? = {
            let candidates = [
                "/opt/homebrew/bin/tmux", // Apple Silicon Homebrew
                "/usr/local/bin/tmux", // Intel Homebrew / manual install
                "/opt/local/bin/tmux", // MacPorts
                "/usr/bin/tmux" // system (rare on macOS)
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }()

        @Sendable func shell(_ arguments: [String]) throws -> String {
            guard let tmuxPath else { throw TmuxClientError.tmuxNotFound }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
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
                let cmd = arguments.first { !$0.hasPrefix("-") } ?? "tmux"
                throw TmuxClientError.commandFailed(
                    command: cmd,
                    exitCode: process.terminationStatus,
                    stderr: errorOutput
                )
            }
            return output
        }

        return TmuxClient(
            createSession: { name, workingDirectory, env in
                // Sorting keys keeps the command line stable for testing and
                // log diffing. Empty env maps to zero `-e` flags, which is
                // equivalent to the previous zero-env `new-session` shape.
                var arguments = ["new-session", "-d", "-s", name, "-c", workingDirectory]
                for (key, value) in env.sorted(by: { $0.key < $1.key }) {
                    arguments.append("-e")
                    arguments.append("\(key)=\(value)")
                }
                _ = try shell(arguments)
            },
            sendKeys: { target, keys in
                // Two args: the key string and a literal `Enter` so the shell
                // actually executes the command instead of leaving it on the
                // prompt.
                _ = try shell(["send-keys", "-t", target, keys, "Enter"])
            },
            hasSession: { name in
                // tmux exits non-zero when the session does not exist OR when no
                // server is running — both mean "no session" for our purposes.
                // The `=` prefix forces an exact name match, not a prefix match.
                // `.tmuxNotFound` deliberately propagates so callers can
                // distinguish "no session" from "tmux not installed".
                do {
                    _ = try shell(["has-session", "-t", "=\(name)"])
                    return true
                } catch TmuxClientError.commandFailed {
                    return false
                }
            },
            killSession: { name in
                _ = try shell(["kill-session", "-t", "=\(name)"])
            },
            listSessions: {
                // `tmux ls` exits non-zero when no server is running. Treat that
                // as "no sessions" rather than an error so reconciliation can
                // run on a clean machine. Filter to `klause-` so unrelated user
                // sessions never appear in the reconciliation set.
                do {
                    let output = try shell(["list-sessions", "-F", "#{session_name}"])
                    guard !output.isEmpty else { return [] }
                    return output
                        .split(separator: "\n")
                        .map(String.init)
                        .filter { $0.hasPrefix("klause-") }
                } catch TmuxClientError.commandFailed {
                    return []
                }
            },
            resolvedTmuxPath: { tmuxPath }
        )
    }()

    nonisolated static let testValue = TmuxClient(
        createSession: unimplemented("TmuxClient.createSession"),
        sendKeys: unimplemented("TmuxClient.sendKeys"),
        hasSession: unimplemented("TmuxClient.hasSession"),
        killSession: unimplemented("TmuxClient.killSession"),
        listSessions: unimplemented("TmuxClient.listSessions"),
        resolvedTmuxPath: unimplemented("TmuxClient.resolvedTmuxPath", placeholder: nil)
    )
}

extension DependencyValues {
    var tmuxClient: TmuxClient {
        get { self[TmuxClient.self] }
        set { self[TmuxClient.self] = newValue }
    }
}
