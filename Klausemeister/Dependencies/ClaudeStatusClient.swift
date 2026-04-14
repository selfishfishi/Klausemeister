// Klausemeister/Dependencies/ClaudeStatusClient.swift
import Dependencies
import Foundation
import OSLog

// MARK: - Model

/// Live state of a meister's Claude Code session as inferred from the
/// per-worktree status file written by the `klause-status-hook.sh` script.
nonisolated enum ClaudeSessionState: Equatable {
    case working(tool: String?)
    case idle
    case blocked
    case error
    case offline
}

// MARK: - Client

struct ClaudeStatusClient {
    /// Point-in-time read for one worktree. Returns `.offline` for missing,
    /// stale (>60s), or malformed files.
    var status: @Sendable (_ worktreeId: String) async -> ClaudeSessionState
    /// Long-lived stream of `(worktreeId, state)` deltas across every
    /// worktree's status file. Emits the initial snapshot of all existing
    /// files on subscription, then one tuple per transition. A periodic
    /// rescan ensures staleness transitions still flow through even when
    /// the filesystem is quiet (e.g. a meister process exited without
    /// firing `SessionEnd`).
    var stateChanges: @Sendable () -> AsyncStream<(worktreeId: String, state: ClaudeSessionState)>
}

extension ClaudeStatusClient: DependencyKey {
    /// Maximum age of a status file before the writer is presumed dead and
    /// the state collapses to `.offline`.
    nonisolated private static let staleAfter: TimeInterval = 60

    /// How often we rescan the status directory independently of file system
    /// events — catches `.offline` transitions caused purely by time passing.
    nonisolated private static let periodicRescanInterval: DispatchTimeInterval = .seconds(15)

    /// `~/.klausemeister/status/`. Must match the path written by
    /// `klause-workflow/hooks/klause-status-hook.sh`.
    nonisolated private static let statusDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".klausemeister/status", isDirectory: true)
    }()

    nonisolated static let liveValue: ClaudeStatusClient = {
        let log = Logger(subsystem: "com.klausemeister", category: "ClaudeStatusClient")

        return ClaudeStatusClient(
            status: { worktreeId in
                let url = Self.statusDirectory.appendingPathComponent("\(worktreeId).json")
                return Self.readState(at: url, now: Date(), log: log)
            },
            stateChanges: {
                AsyncStream { continuation in
                    // Ensure the directory exists — the hook creates it lazily,
                    // but the watcher needs an fd at subscription time.
                    try? FileManager.default.createDirectory(
                        at: Self.statusDirectory,
                        withIntermediateDirectories: true
                    )

                    let queue = DispatchQueue(
                        label: "com.klausemeister.claude-status-watcher",
                        qos: .utility
                    )

                    // Snapshot of the last state emitted per worktree id.
                    // Only mutated from `queue`, so no locking needed.
                    var lastKnown: [String: ClaudeSessionState] = [:]

                    func rescanAndEmit() {
                        let now = Date()
                        guard let files = try? FileManager.default.contentsOfDirectory(
                            at: Self.statusDirectory,
                            includingPropertiesForKeys: nil
                        ) else {
                            log.warning("rescan: failed to list status dir")
                            return
                        }

                        var seenIds: Set<String> = []
                        for file in files where file.pathExtension == "json" {
                            let worktreeId = file.deletingPathExtension().lastPathComponent
                            seenIds.insert(worktreeId)
                            let state = Self.readState(at: file, now: now, log: log)
                            if lastKnown[worktreeId] != state {
                                lastKnown[worktreeId] = state
                                continuation.yield((worktreeId, state))
                            }
                        }

                        // Any id we had previously but no longer see on disk
                        // has transitioned to offline.
                        for (id, prevState) in lastKnown where !seenIds.contains(id)
                            && prevState != .offline
                        {
                            lastKnown[id] = .offline
                            continuation.yield((id, .offline))
                        }
                    }

                    let dirFD = open(Self.statusDirectory.path, O_EVTONLY)
                    guard dirFD >= 0 else {
                        log.warning(
                            "failed to open status directory \(Self.statusDirectory.path) (errno \(errno)); watcher inactive"
                        )
                        continuation.finish()
                        return
                    }

                    let dirSource = DispatchSource.makeFileSystemObjectSource(
                        fileDescriptor: dirFD,
                        eventMask: [.write, .rename, .delete, .extend],
                        queue: queue
                    )
                    dirSource.setEventHandler { rescanAndEmit() }
                    dirSource.setCancelHandler { close(dirFD) }

                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(
                        deadline: .now() + Self.periodicRescanInterval,
                        repeating: Self.periodicRescanInterval
                    )
                    timer.setEventHandler { rescanAndEmit() }

                    continuation.onTermination = { _ in
                        dirSource.cancel()
                        timer.cancel()
                    }

                    // Initial snapshot so subscribers see existing state without
                    // waiting for the first FS event.
                    queue.async { rescanAndEmit() }

                    dirSource.resume()
                    timer.resume()
                }
            }
        )
    }()

    nonisolated static let testValue = ClaudeStatusClient(
        status: unimplemented("ClaudeStatusClient.status", placeholder: .offline),
        stateChanges: unimplemented(
            "ClaudeStatusClient.stateChanges",
            placeholder: AsyncStream { $0.finish() }
        )
    )
}

// MARK: - File decoding

/// On-disk representation produced by `klause-status-hook.sh`. Any decode
/// error or unknown `state` string collapses to `.offline` rather than
/// surfacing an error — the status layer must never fail loud.
nonisolated private struct StatusFilePayload: Decodable {
    let state: String
    let timestamp: Int
    let sessionId: String?
    let lastTool: String?

    private enum CodingKeys: String, CodingKey {
        case state
        case timestamp
        case sessionId = "session_id"
        case lastTool = "last_tool"
    }
}

private extension ClaudeStatusClient {
    nonisolated static func readState(at url: URL, now: Date, log: Logger) -> ClaudeSessionState {
        guard let data = try? Data(contentsOf: url) else { return .offline }
        let payload: StatusFilePayload
        do {
            payload = try JSONDecoder().decode(StatusFilePayload.self, from: data)
        } catch {
            log.debug(
                "ignoring malformed status file \(url.path): \(String(describing: error))"
            )
            return .offline
        }

        let age = now.timeIntervalSince1970 - TimeInterval(payload.timestamp)
        if age > staleAfter { return .offline }

        switch payload.state {
        case "working": return .working(tool: payload.lastTool)
        case "idle": return .idle
        case "blocked": return .blocked
        case "error": return .error
        default:
            log.debug("ignoring unknown state '\(payload.state)' in \(url.path)")
            return .offline
        }
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    var claudeStatusClient: ClaudeStatusClient {
        get { self[ClaudeStatusClient.self] }
        set { self[ClaudeStatusClient.self] = newValue }
    }
}
