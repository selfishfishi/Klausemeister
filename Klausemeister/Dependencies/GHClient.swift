// Klausemeister/Dependencies/GHClient.swift
import Dependencies
import Foundation
import OSLog

struct GHClient {
    var prForBranch: @Sendable (
        _ repoPath: String,
        _ branchName: String
    ) async throws -> PRInfo?

    struct PRInfo: Equatable {
        let number: Int
        let state: PRState
    }
}

/// PR lifecycle state. Parsed once at the GHClient boundary from GitHub's
/// JSON response; carried as a value through GitStats.PRSummary into views.
enum PRState: String, Equatable {
    case open = "OPEN"
    case merged = "MERGED"
    case closed = "CLOSED"
}

enum GHClientError: Error, Equatable, LocalizedError {
    case ghNotFound
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .ghNotFound:
            "GitHub CLI not found. Install via `brew install gh` and run `gh auth login`."
        case let .commandFailed(command, exitCode, stderr):
            "gh \(command) failed (exit \(exitCode)): \(stderr)"
        }
    }
}

// MARK: - Live & Test values

extension GHClient: DependencyKey {
    nonisolated static let liveValue: GHClient = {
        let log = Logger(subsystem: "com.klausemeister", category: "GHClient")

        let ghPath: String? = {
            let candidates = [
                "/opt/homebrew/bin/gh",
                "/usr/local/bin/gh",
                "/opt/local/bin/gh",
                "/usr/bin/gh"
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }()

        @Sendable func shell(_ arguments: [String], cwd: String? = nil) throws -> String {
            guard let ghPath else { throw GHClientError.ghNotFound }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = arguments
            if let cwd {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()

            // Read pipes BEFORE waitUntilExit to avoid deadlock if output
            // exceeds the 64KB pipe buffer.
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw GHClientError.commandFailed(
                    command: arguments.first ?? "gh",
                    exitCode: process.terminationStatus,
                    stderr: errorOutput
                )
            }
            return output
        }

        return GHClient(
            prForBranch: { repoPath, branchName in
                guard ghPath != nil else {
                    log.info("gh CLI not installed — PR info unavailable")
                    return nil
                }
                let output: String
                do {
                    output = try shell([
                        "pr", "view", branchName,
                        "--json", "number,state"
                    ], cwd: repoPath)
                } catch let error as GHClientError {
                    if case let .commandFailed(_, _, stderr) = error,
                       stderr.contains("no pull requests found")
                    {
                        return nil
                    }
                    throw error
                }
                guard let data = output.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let number = json["number"] as? Int,
                      let stateStr = json["state"] as? String,
                      let state = PRState(rawValue: stateStr)
                else {
                    log.warning("Failed to parse gh pr view JSON: \(output)")
                    return nil
                }
                return PRInfo(number: number, state: state)
            }
        )
    }()

    nonisolated static let testValue = GHClient(
        prForBranch: unimplemented("GHClient.prForBranch")
    )
}

extension DependencyValues {
    var ghClient: GHClient {
        get { self[GHClient.self] }
        set { self[GHClient.self] = newValue }
    }
}
