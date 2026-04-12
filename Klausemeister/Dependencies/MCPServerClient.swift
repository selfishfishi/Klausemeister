// Klausemeister/Dependencies/MCPServerClient.swift
import Dependencies
import Foundation

/// TCA dependency client wrapping the in-process MCP server.
///
/// `start()` boots the Unix-socket listener (defined in
/// `Klausemeister/MCP/MCPSocketListener.swift`) and returns only when it
/// terminates — typically when the app quits and the effect is cancelled.
///
/// `events()` returns the bridge `AsyncStream` over which the listener pushes
/// errors and progress reports back into TCA. `AppFeature` consumes it via a
/// long-lived `.run` effect, mirroring how `OAuthClient` bridges callback URLs.
struct MCPServerClient {
    var start: @Sendable () async -> Void

    /// Returns the single event stream from the MCP server.
    /// WARNING: `AsyncStream` is single-consumer — calling this from
    /// two `for await` loops concurrently will race and drop events.
    /// Only `AppFeature.onAppear` should consume this stream.
    var events: @Sendable () -> AsyncStream<MCPServerEvent>

    /// Scans `~/.klausemeister/shim-state/` for active shim state files,
    /// checks if their PIDs are alive, and returns discovery results.
    /// Stale files (dead PIDs) are cleaned up.
    var discoverActiveShims: @Sendable () async -> [ShimDiscoveryResult]

    /// Rich scan for the debug panel: returns full shim info + system diagnostics.
    var scanShimDiagnostics: @Sendable () async -> ShimDiagnosticsResult
}

/// Result of scanning a shim state file. Only `"connected"` status causes
/// the app to set `meisterStatus = .running`; other statuses are informational.
struct ShimDiscoveryResult: Equatable {
    let worktreeId: String
    let status: String
}

/// Rich shim info for the debug panel — includes PID, timestamps, liveness.
struct ShimStateInfo: Equatable, Identifiable {
    var id: String {
        worktreeId
    }

    let worktreeId: String
    let pid: Int32
    let status: String
    let socketPath: String
    let timestamp: String
    let isAlive: Bool
}

/// Aggregated diagnostics result from scanning shim state files + system info.
struct ShimDiagnosticsResult: Equatable {
    let shimStates: [ShimStateInfo]
    let shimSymlinkTarget: String
    let socketExists: Bool
}

// MARK: - State file decoding (mirrors shim's ShimStateFile)

private struct ShimStateFile: Decodable {
    let worktreeId: String
    let pid: Int32
    let status: String
    let socketPath: String?
    let timestamp: String?
}

extension MCPServerClient: DependencyKey {
    nonisolated static let liveValue: MCPServerClient = {
        let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)
        let listener = MCPSocketListener()

        return MCPServerClient(
            start: {
                await listener.run(eventContinuation: continuation)
            },
            events: { stream },
            discoverActiveShims: {
                await scanShimStateFiles().0
            },
            scanShimDiagnostics: {
                let (discoveryResults, shimStates) = await scanShimStateFiles()
                _ = discoveryResults
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let symlinkPath = "\(home)/.klausemeister/bin/klause-mcp-shim"
                let symlinkTarget = (try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath)) ?? ""
                let socketPath = MCPSocketListener.socketPath
                let socketExists = FileManager.default.fileExists(atPath: socketPath)
                return ShimDiagnosticsResult(
                    shimStates: shimStates,
                    shimSymlinkTarget: symlinkTarget,
                    socketExists: socketExists
                )
            }
        )
    }()

    /// Shared scan logic returning both discovery results and rich shim info.
    private static func scanShimStateFiles() async -> ([ShimDiscoveryResult], [ShimStateInfo]) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.klausemeister/shim-state"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return ([], [])
        }
        let decoder = JSONDecoder()
        var discoveryResults: [ShimDiscoveryResult] = []
        var shimStates: [ShimStateInfo] = []
        for entry in entries where entry.hasSuffix(".json") {
            let path = "\(dir)/\(entry)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let file = try? decoder.decode(ShimStateFile.self, from: data)
            else {
                try? FileManager.default.removeItem(atPath: path)
                continue
            }
            let alive = kill(file.pid, 0) == 0
            shimStates.append(ShimStateInfo(
                worktreeId: file.worktreeId,
                pid: file.pid,
                status: file.status,
                socketPath: file.socketPath ?? "",
                timestamp: file.timestamp ?? "",
                isAlive: alive
            ))
            if alive {
                discoveryResults.append(ShimDiscoveryResult(
                    worktreeId: file.worktreeId,
                    status: file.status
                ))
            } else {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        return (discoveryResults, shimStates)
    }

    nonisolated static let testValue = MCPServerClient(
        start: unimplemented("MCPServerClient.start"),
        events: unimplemented("MCPServerClient.events", placeholder: AsyncStream { _ in }),
        discoverActiveShims: unimplemented("MCPServerClient.discoverActiveShims", placeholder: []),
        scanShimDiagnostics: unimplemented(
            "MCPServerClient.scanShimDiagnostics",
            placeholder: ShimDiagnosticsResult(shimStates: [], shimSymlinkTarget: "", socketExists: false)
        )
    )
}

extension DependencyValues {
    var mcpServerClient: MCPServerClient {
        get { self[MCPServerClient.self] }
        set { self[MCPServerClient.self] = newValue }
    }
}
