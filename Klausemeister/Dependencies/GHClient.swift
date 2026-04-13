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

        // Runs a gh CLI subprocess using event-driven I/O (readabilityHandler
        // + terminationHandler) so no thread is blocked for the lifetime of
        // the process.
        // swiftlint:disable:next function_body_length
        @Sendable func shell(_ arguments: [String], cwd: String? = nil) async throws -> String {
            guard let ghPath else { throw GHClientError.ghNotFound }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = arguments
            if let cwd {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }
            process.standardInput = FileHandle.nullDevice
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let collector = DispatchQueue(label: "com.klausemeister.gh-pipe")
                    var outputData = Data()
                    var errorData = Data()
                    var stdoutDone = false
                    var stderrDone = false
                    var processDone = false
                    var resumed = false

                    func tryFinish() {
                        dispatchPrecondition(condition: .onQueue(collector))
                        guard stdoutDone, stderrDone, processDone, !resumed else { return }
                        resumed = true
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        let output = String(data: outputData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let errorOutput = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                        if process.terminationReason == .uncaughtSignal, Task.isCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        guard process.terminationStatus == 0 else {
                            continuation.resume(throwing: GHClientError.commandFailed(
                                command: arguments.first ?? "gh",
                                exitCode: process.terminationStatus,
                                stderr: errorOutput
                            ))
                            return
                        }
                        continuation.resume(returning: output)
                    }

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        collector.async {
                            if data.isEmpty {
                                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                                stdoutDone = true
                                tryFinish()
                            } else {
                                outputData.append(data)
                            }
                        }
                    }

                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        collector.async {
                            if data.isEmpty {
                                stderrPipe.fileHandleForReading.readabilityHandler = nil
                                stderrDone = true
                                tryFinish()
                            } else {
                                errorData.append(data)
                            }
                        }
                    }

                    process.terminationHandler = { _ in
                        collector.async {
                            processDone = true
                            tryFinish()
                        }
                    }

                    do {
                        try process.run()
                    } catch {
                        collector.async {
                            guard !resumed else { return }
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
        }

        return GHClient(
            prForBranch: { repoPath, branchName in
                guard ghPath != nil else {
                    log.info("gh CLI not installed — PR info unavailable")
                    return nil
                }
                let output: String
                do {
                    output = try await shell([
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
