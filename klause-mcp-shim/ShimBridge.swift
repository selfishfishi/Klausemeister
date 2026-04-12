// klause-mcp-shim/ShimBridge.swift
// Resilient stdio↔Unix-socket bridge. Survives app restarts via kqueue
// reconnect. Persists state to ~/.klausemeister/shim-state/ for discovery.
import Foundation

/// File-based debug logging shared between main.swift and ShimBridge.
func shimDebugLog(_ message: String) {
    let path = "/tmp/klause-shim-debug.log"
    let entry = Data("[\(Date())] [pid=\(getpid())] \(message)\n".utf8)
    guard let handle = FileHandle(forWritingAtPath: path) ?? {
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }() else { return }
    handle.seekToEndOfFile()
    handle.write(entry)
    handle.closeFile()
}

// MARK: - Connection state

/// The states the bridge cycles through. Associated values hold the resources
/// that must be torn down on state transition.
private enum ConnectionState {
    case connected(
        socketFD: Int32,
        stdinSource: DispatchSourceRead,
        socketSource: DispatchSourceRead
    )
    case watching(
        dirFD: Int32,
        dirSource: DispatchSourceFileSystemObject,
        stdinSource: DispatchSourceRead,
        retryTimer: DispatchSourceTimer?
    )
    /// Fallback when the socket directory doesn't exist yet. The timer polls
    /// for directory creation; once it appears we transition to `.watching`.
    case polling(
        stdinSource: DispatchSourceRead,
        timer: DispatchSourceTimer
    )
}

// MARK: - State file

/// Persisted to disk for discovery by the respawn wrapper and Klausemeister.
struct ShimStateFile: Codable {
    var worktreeId: String
    var pid: Int32
    var status: String
    var socketPath: String
    var timestamp: String
}

// MARK: - ShimBridge

final class ShimBridge {
    let socketPath: String
    private let socketDir: String
    let worktreeId: String
    private let helloData: Data
    let stateFilePath: String

    /// Serial queue that protects all state mutations. Every DispatchSource
    /// targets this queue so handlers never race.
    private let stateQueue = DispatchQueue(label: "klause-mcp-shim.state")

    private var state: ConnectionState?

    /// Line buffer for the disconnected stdin source. Accumulates bytes until
    /// a newline is found, then hands off complete lines for error synthesis.
    /// Capped at `maxLineBufferSize` to prevent unbounded growth.
    private var stdinLineBuffer = Data()
    private let maxLineBufferSize = 1_048_576 // 1 MB

    init?(socketPath: String, worktreeId: String) {
        self.socketPath = socketPath
        socketDir = (socketPath as NSString).deletingLastPathComponent
        self.worktreeId = worktreeId

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        stateFilePath = "\(home)/.klausemeister/shim-state/\(worktreeId).json"

        let hello = HelloFrame(klauseMeister: "1", klauseWorktreeId: worktreeId)
        guard var data = try? JSONEncoder().encode(hello) else {
            FileHandle.standardError.write(Data("klause-mcp-shim: failed to encode hello frame\n".utf8))
            return nil
        }
        data.append(0x0A)
        helloData = data
    }

    // MARK: - Entry point

    /// Attempts initial connection. On success starts the pump; on failure
    /// enters the filesystem watcher. Then parks on `dispatchMain()`.
    func run() -> Never {
        stateQueue.sync {
            if let socketFD = attemptConnect() {
                guard sendHello(socketFD: socketFD) else {
                    close(socketFD)
                    log("hello send failed on initial connect")
                    startWatching()
                    return
                }
                log("connected to \(socketPath)")
                startPump(socketFD: socketFD)
            } else {
                log("Klausemeister not available, waiting for connection")
                startWatching()
            }
        }
        dispatchMain()
    }

    // MARK: - Connection

    /// Attempts `connect()` to `socketPath`. Returns the connected FD or nil.
    /// Sets `O_NONBLOCK` on both the socket FD and `STDOUT_FILENO` on success.
    private func attemptConnect() -> Int32? {
        let sockFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockFD >= 0 else {
            log("socket() failed: \(String(cString: strerror(errno)))")
            return nil
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(sockFD)
            return nil
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { cPtr in
                for (idx, byte) in pathBytes.enumerated() {
                    cPtr[idx] = CChar(bitPattern: byte)
                }
                cPtr[pathBytes.count] = 0
            }
        }

        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sockFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            log("connect failed: \(String(cString: strerror(errno)))")
            close(sockFD)
            return nil
        }

        guard setNonBlocking(sockFD), setNonBlocking(STDOUT_FILENO) else {
            log("fcntl O_NONBLOCK failed: \(String(cString: strerror(errno)))")
            close(sockFD)
            return nil
        }

        return sockFD
    }

    /// Sets `O_NONBLOCK` on a file descriptor. Returns false on failure.
    private func setNonBlocking(_ fileDescriptor: Int32) -> Bool {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0
    }

    /// Writes `data` fully to `fileDescriptor`, retrying on partial writes.
    /// Retries on `EAGAIN`/`EWOULDBLOCK` (transient back-pressure on
    /// non-blocking FDs) up to ~5 seconds. Returns false on permanent failure
    /// or if EAGAIN persists beyond the retry limit.
    private func writeAll(_ fileDescriptor: Int32, _ data: UnsafeRawBufferPointer) -> Bool {
        guard let base = data.baseAddress else { return true }
        var written = 0
        var eagainRetries = 0
        let maxEagainRetries = 5000 // ~5 seconds at 1ms per retry
        while written < data.count {
            let bytesWritten = write(fileDescriptor, base.advanced(by: written), data.count - written)
            if bytesWritten > 0 {
                written += bytesWritten
                eagainRetries = 0
            } else if bytesWritten < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                eagainRetries += 1
                if eagainRetries > maxEagainRetries {
                    log("writeAll: giving up after \(eagainRetries) EAGAIN retries")
                    return false
                }
                usleep(1000)
            } else {
                return false
            }
        }
        return true
    }

    /// Sends the pre-encoded HelloFrame on the given socket.
    private func sendHello(socketFD: Int32) -> Bool {
        helloData.withUnsafeBytes { writeAll(socketFD, $0) }
    }

    // MARK: - Pump (CONNECTED state)

    /// Creates and resumes the two bidirectional pump DispatchSources.
    /// Transitions state to `.connected`. Must be called on `stateQueue`.
    private func startPump(socketFD: Int32) {
        let stdinSrc = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO,
            queue: stateQueue
        )
        let socketSrc = DispatchSource.makeReadSource(
            fileDescriptor: socketFD,
            queue: stateQueue
        )

        // stdin → socket
        stdinSrc.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = buffer.withUnsafeMutableBufferPointer { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if bytesRead <= 0 {
                handleStdinEOF()
                return
            }
            let writeOK = buffer.withUnsafeBytes {
                self.writeAll(socketFD, UnsafeRawBufferPointer(rebasing: $0.prefix(bytesRead)))
            }
            if !writeOK {
                handleSocketDeath()
            }
        }

        // socket → stdout
        socketSrc.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = buffer.withUnsafeMutableBufferPointer { read(socketFD, $0.baseAddress, $0.count) }
            if bytesRead <= 0 {
                handleSocketDeath()
                return
            }
            let writeOK = buffer.withUnsafeBytes {
                self.writeAll(STDOUT_FILENO, UnsafeRawBufferPointer(rebasing: $0.prefix(bytesRead)))
            }
            if !writeOK {
                // stdout broken means Claude Code is gone, not the socket.
                log("stdout write failed, meister gone")
                handleStdinEOF()
            }
        }

        state = .connected(socketFD: socketFD, stdinSource: stdinSrc, socketSource: socketSrc)
        writeStateFile(status: "connected")
        stdinSrc.resume()
        socketSrc.resume()
    }

    // MARK: - Disconnect handling

    /// Tears down the pump, closes the socket, and transitions to WATCHING.
    /// `shutdown` is called before `close` so the deferred cancel handlers
    /// don't operate on a potentially reused FD number.
    /// Must be called on `stateQueue`.
    private func handleSocketDeath() {
        guard case let .connected(socketFD, stdinSrc, socketSrc) = state else { return }
        shutdown(socketFD, SHUT_WR)
        stdinSrc.cancel()
        socketSrc.cancel()
        close(socketFD)
        log("connection lost, watching for reconnect")
        stdinLineBuffer.removeAll()
        startWatching()
    }

    /// stdin EOF means the meister process is gone. Delete the state file
    /// (clean exit) then terminate. Process exit handles all resource cleanup
    /// (open FDs, DispatchSources).
    private func handleStdinEOF() {
        log("stdin closed (EOF), deleting state file, exiting with code 0")
        deleteStateFile()
        exit(0)
    }

    // MARK: - Filesystem watching (WATCHING state)

    /// Sets up a kqueue-backed DispatchSource on the socket's parent directory
    /// to detect when a new `klause.sock` is created. If the directory doesn't
    /// exist yet, falls back to a 2s repeating timer that polls for it.
    /// Must be called on `stateQueue`.
    private func startWatching() {
        let dirFD = open(socketDir, O_EVTONLY)
        if dirFD < 0 {
            // Directory doesn't exist yet — poll for its creation.
            startDirectoryPolling()
            return
        }

        let dirSrc = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: stateQueue
        )
        dirSrc.setEventHandler { [weak self] in
            self?.attemptReconnect()
        }
        dirSrc.setCancelHandler {
            close(dirFD)
        }

        let stdinSrc = makeDisconnectedStdinSource()
        state = .watching(dirFD: dirFD, dirSource: dirSrc, stdinSource: stdinSrc, retryTimer: nil)
        writeStateFile(status: "watching")
        dirSrc.resume()
        stdinSrc.resume()

        // Socket file might already exist (e.g. app relaunched before we
        // set up the watcher). Try immediately.
        attemptReconnect()
    }

    /// Fallback when the socket directory doesn't exist. Polls every 2s until
    /// the directory appears, then switches to kqueue watching.
    private func startDirectoryPolling() {
        let stdinSrc = makeDisconnectedStdinSource()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let dirFD = open(socketDir, O_EVTONLY)
            if dirFD >= 0 {
                close(dirFD)
                // Directory appeared. Tear down polling state and switch
                // to proper kqueue watching.
                tearDownPolling()
                startWatching()
            }
        }

        state = .polling(stdinSource: stdinSrc, timer: timer)
        writeStateFile(status: "polling")
        stdinSrc.resume()
        timer.resume()
    }

    /// Cancels the polling sources. Must be called on `stateQueue`.
    private func tearDownPolling() {
        guard case let .polling(stdinSrc, timer) = state else { return }
        timer.cancel()
        stdinSrc.cancel()
    }

    /// Attempts to reconnect to the socket. On success, tears down watching
    /// state and starts the pump. On failure, schedules a retry timer.
    /// Must be called on `stateQueue`.
    private func attemptReconnect() {
        // Guard: only reconnect from the watching state.
        guard case .watching = state else { return }

        guard let socketFD = attemptConnect() else {
            scheduleRetryTimer()
            return
        }

        guard sendHello(socketFD: socketFD) else {
            close(socketFD)
            scheduleRetryTimer()
            return
        }

        // Success — tear down watching state.
        if case let .watching(_, dirSrc, stdinSrc, retryTimer) = state {
            dirSrc.cancel()
            stdinSrc.cancel()
            retryTimer?.cancel()
        }

        log("reconnected")
        stdinLineBuffer.removeAll()
        startPump(socketFD: socketFD)
    }

    /// Schedules a one-shot 500ms timer to retry `attemptReconnect()`.
    /// Handles the race where kqueue fires on socket file creation before the
    /// app has called `listen()` on it.
    /// Must be called on `stateQueue`.
    private func scheduleRetryTimer() {
        guard case let .watching(dirFD, dirSrc, stdinSrc, existingTimer) = state else { return }
        existingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.attemptReconnect()
        }

        state = .watching(dirFD: dirFD, dirSource: dirSrc, stdinSource: stdinSrc, retryTimer: timer)
        timer.resume()
    }

    // MARK: - Logging

    func log(_ message: String) {
        FileHandle.standardError.write(Data("klause-mcp-shim: \(message)\n".utf8))
        shimDebugLog(message)
    }
}

// MARK: - Error synthesis (during WATCHING / POLLING)

extension ShimBridge {
    /// Creates a DispatchSource on stdin that reads JSON-RPC requests during
    /// disconnect and writes error responses so the meister doesn't hang.
    func makeDisconnectedStdinSource() -> DispatchSourceRead {
        let src = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO,
            queue: stateQueue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = buffer.withUnsafeMutableBufferPointer { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if bytesRead <= 0 {
                handleStdinEOF()
                return
            }
            stdinLineBuffer.append(contentsOf: buffer.prefix(bytesRead))
            if stdinLineBuffer.count > maxLineBufferSize {
                log("stdin line buffer exceeded \(maxLineBufferSize) bytes, discarding")
                stdinLineBuffer.removeAll()
            }
            drainLineBuffer()
        }
        return src
    }

    /// Extracts complete lines from `stdinLineBuffer` and synthesizes error
    /// responses for each JSON-RPC request found.
    func drainLineBuffer() {
        while let newlineIndex = stdinLineBuffer.firstIndex(of: 0x0A) {
            let line = stdinLineBuffer[stdinLineBuffer.startIndex ..< newlineIndex]
            stdinLineBuffer.removeSubrange(stdinLineBuffer.startIndex ... newlineIndex)
            if let response = synthesizeErrorResponse(forLine: Data(line)) {
                let writeOK = response.withUnsafeBytes { bytes in
                    writeAll(STDOUT_FILENO, bytes)
                }
                if !writeOK {
                    handleStdinEOF()
                    return
                }
            }
        }
    }

    /// Parses a JSON-RPC line. If it's a request (has `"method"` and a string
    /// or number `"id"`), returns a JSON-RPC error response. Returns nil for
    /// notifications (no `"id"`), unparseable input, or null/container `id`
    /// values.
    func synthesizeErrorResponse(forLine line: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["method"] != nil,
              let rawID = json["id"],
              rawID is String || rawID is NSNumber
        else { return nil }

        let errorResponse: [String: Any] = [
            "jsonrpc": "2.0",
            "id": rawID,
            "error": [
                "code": -32000,
                "message": "Klausemeister is not running"
            ]
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: errorResponse) else {
            log("failed to serialize JSON-RPC error response")
            return nil
        }
        data.append(0x0A)
        return data
    }
}
