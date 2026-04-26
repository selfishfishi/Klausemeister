// KlauseMCPShim/main.swift
//
// Resilient stdio↔Unix-socket bridge between the meister Claude Code and
// Klausemeister.app. This binary serves two roles depending on the
// `KLAUSE_SHIM_WORKER` environment variable:
//
// **Wrapper mode** (default, no env var): spawns itself as a child process
// in worker mode, waits for it to exit, and respawns on unexpected death
// (SIGTERM, SIGKILL, crash) with exponential backoff. Intentional exits
// (codes 0, 2, 3, 4) propagate without respawn.
//
// **Worker mode** (`KLAUSE_SHIM_WORKER=1`): the actual MCP bridge. Forwards
// bytes between Claude Code's stdio and Klausemeister's Unix socket, with
// kqueue-based reconnect and JSON-RPC error synthesis during disconnects.
//
// IMPORTANT: This file is the entry point of a separate Xcode target
// (`KlauseMCPShim`, a Command Line Tool). The `HelloFrame` struct it shares
// with the app comes from `Klausemeister/MCP/HelloFrame.swift`, which is
// added to BOTH targets via Xcode's multi-target file membership.
import Foundation

// MARK: - Debug logging (writes to /tmp/klause-shim-debug.log)

/// Alias for the shared debug logger in ShimBridge.swift.
private func debugLog(_ message: String) {
    shimDebugLog(message)
}

// Ignore SIGPIPE so writing to a broken socket/pipe returns EPIPE instead of
// killing the process. Critical for both wrapper and worker: without this, a
// broken pipe terminates before any error handling can fire.
signal(SIGPIPE, SIG_IGN)

// MARK: - Wrapper / Worker branch

let env = ProcessInfo.processInfo.environment

let workerFlag = env["KLAUSE_SHIM_WORKER"] ?? "<nil>"
let meisterFlag = env["KLAUSE_MEISTER"] ?? "<nil>"
let worktreeFlag = env["KLAUSE_WORKTREE_ID"] ?? "<nil>"
debugLog("started, WORKER=\(workerFlag), MEISTER=\(meisterFlag), WT=\(worktreeFlag)")

// Codex registers `klausemeister` globally in `~/.codex/config.toml`, so
// it tries to spawn the shim on every Codex session — including plain
// `codex` invocations outside any meister context. In that path
// `KLAUSE_MEISTER` is unset; pre-fix, the shim exited 2 here and Codex
// surfaced "MCP startup failed: connection closed: initialize response".
// Take the stub-server branch instead so non-meister sessions see a
// healthy 0-tool MCP server. Skips wrapper/worker entirely — no real
// socket bridge to babysit.
if env["KLAUSE_MEISTER"] != "1" {
    debugLog("KLAUSE_MEISTER missing/!=1, entering stub MCP server")
    StubMCPServer.run()
}

if env["KLAUSE_SHIM_WORKER"] == nil {
    debugLog("entering wrapper mode")
    runWrapper()
}

debugLog("entering worker mode")

// ── Worker mode below ───────────────────────────────────────────────────

// MARK: - Env validation

// `KLAUSE_MEISTER` was already verified at the top to be "1"; here we
// validate the worktree id which is required for the socket bridge.
guard let worktreeId = env["KLAUSE_WORKTREE_ID"], !worktreeId.isEmpty else {
    FileHandle.standardError.write(Data("klause-mcp-shim: KLAUSE_WORKTREE_ID must be set\n".utf8))
    exit(2)
}

// MARK: - Socket path

// Prefer KLAUSE_SOCKET_PATH env var (set by Klausemeister when spawning the
// meister) so the app is the single source of truth for the socket location.
// Fall back to the conventional path for manual testing.

let socketPath: String = env["KLAUSE_SOCKET_PATH"] ?? {
    guard let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else {
        FileHandle.standardError.write(Data("klause-mcp-shim: cannot resolve Application Support directory\n".utf8))
        exit(3)
    }
    return appSupport
        .appendingPathComponent("Klausemeister")
        .appendingPathComponent("klause.sock")
        .path
}()

// MARK: - Wrapper implementation

/// PID of the current child worker. Accessed from the SIGTERM handler (which
/// must be a C-compatible function), so this is a file-scope global.
/// `nonisolated(unsafe)` because it's read from the signal handler concurrently
/// with writes from `spawnAndWaitForWorker`. Safe for `pid_t` (Int32) on arm64
/// due to natural alignment guaranteeing atomic loads/stores.
nonisolated(unsafe) private var wrapperChildPID: pid_t = 0

/// Spawns itself as a worker child in a loop, respawning on unexpected death.
/// Intentional exit codes (0, 2, 3, 4) propagate without respawn.
/// Never returns — calls `exit()`.
private func runWrapper() -> Never {
    // Forward SIGTERM to the child so it can clean up (delete state file).
    // Only async-signal-safe functions allowed inside the handler.
    signal(SIGTERM) { _ in
        if wrapperChildPID > 0 {
            kill(wrapperChildPID, SIGTERM)
        }
        _exit(0)
    }

    let selfPath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    debugLog("wrapper selfPath=\(selfPath)")
    var backoff: TimeInterval = 1.0
    let maxBackoff: TimeInterval = 30.0
    var consecutiveFastFailures = 0
    let maxConsecutiveFastFailures = 5

    while true {
        let startTime = Date()
        debugLog("wrapper spawning worker")
        let exitCode = spawnAndWaitForWorker(selfPath: selfPath)

        let elapsed = Date().timeIntervalSince(startTime)
        debugLog("wrapper: worker exited, code=\(exitCode.map(String.init) ?? "signal"), elapsed=\(Int(elapsed))s")

        // Intentional exits — propagate without respawn.
        if let code = exitCode, [0, 2, 3, 4].contains(code) {
            debugLog("wrapper: intentional exit code \(code), propagating")
            exit(code)
        }

        // Track consecutive fast failures to avoid infinite respawn loops
        // (e.g. binary moved after app update).
        if elapsed < 5 {
            consecutiveFastFailures += 1
            if consecutiveFastFailures >= maxConsecutiveFastFailures {
                debugLog("wrapper: \(maxConsecutiveFastFailures) consecutive fast failures, giving up")
                exit(1)
            }
        } else {
            consecutiveFastFailures = 0
            backoff = 1.0
        }

        debugLog("wrapper: unexpected death, respawning in \(Int(backoff))s (backoff)")
        FileHandle.standardError.write(
            Data("klause-mcp-shim: worker exited unexpectedly, respawning in \(Int(backoff))s\n".utf8)
        )
        Thread.sleep(forTimeInterval: backoff)
        backoff = min(backoff * 2, maxBackoff)
    }
}

/// Spawns the shim binary as a child with `KLAUSE_SHIM_WORKER=1`, inheriting
/// stdin/stdout/stderr. Blocks until the child exits. Returns the exit code,
/// or nil if the child was terminated by a signal.
private func spawnAndWaitForWorker(selfPath: String) -> Int32? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: selfPath)

    // Inherit stdio so the child talks directly to Claude Code.
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    // Copy current env and add the worker flag.
    var childEnv = ProcessInfo.processInfo.environment
    childEnv["KLAUSE_SHIM_WORKER"] = "1"
    process.environment = childEnv

    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(
            Data("klause-mcp-shim: failed to spawn worker: \(error.localizedDescription)\n".utf8)
        )
        return 1
    }

    wrapperChildPID = process.processIdentifier
    process.waitUntilExit()
    wrapperChildPID = 0

    if process.terminationReason == .exit {
        return process.terminationStatus
    }
    // Terminated by signal — return nil to trigger respawn.
    return nil
}

// MARK: - Run worker

guard let bridge = ShimBridge(socketPath: socketPath, worktreeId: worktreeId) else {
    exit(4)
}

bridge.run()
