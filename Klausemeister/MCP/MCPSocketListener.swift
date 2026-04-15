// swiftlint:disable file_length
// Klausemeister/MCP/MCPSocketListener.swift
import Foundation
import Logging
import MCP
import os.log

/// Owns the Unix-domain-socket listener for the in-process MCP server.
///
/// `MCPSocketListener.run(eventContinuation:)` is called once at app start by
/// `MCPServerClient.liveValue.start`. It:
///   1. Installs the shim symlink so the plugin can find the helper.
///   2. Unlinks any stale socket file from a previous app run.
///   3. Binds an `NWListener` to the socket path and accepts connections.
///   4. For each connection: reads the `HelloFrame`, validates the meister
///      identity, then constructs a per-connection `SocketTransport` + MCP
///      `Server` with tool handlers closing over the worktree id.
///   5. Yields any errors encountered to `eventContinuation` so they reach
///      `StatusBarFeature` via the `AppFeature` bridge.
///
/// The function returns only when the underlying `.run` effect is cancelled
/// (i.e. when the app is shutting down).
nonisolated private func debugLog(_ message: String) {
    let path = "/tmp/klause-mcp-debug.log"
    guard let handle = FileHandle(forWritingAtPath: path) ?? {
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }() else { return }
    handle.seekToEndOfFile()
    handle.write(Data("[\(Date())] \(message)\n".utf8))
    handle.closeFile()
}

actor MCPSocketListener {
    /// Hard-coded socket path. Klausemeister assumes a single instance per
    /// machine; if you ever run two copies they will fight for this path.
    static let socketPath: String = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Klausemeister")
        return appSupport.appendingPathComponent("klause.sock").path
    }()

    /// Where the shim helper is symlinked on first launch. The path must
    /// be **space-free** because Claude Code's MCP launcher splits the
    /// `command` string on whitespace before spawning — a path like
    /// `~/Library/Application Support/…` silently breaks into a wrong
    /// executable + spurious argument. `~/.klausemeister/bin/` avoids this.
    static let shimSymlinkPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".klausemeister/bin/klause-mcp-shim")
            .path
    }()

    private static let logger = Logger(label: "klausemeister.mcp.listener")

    // MARK: - Per-worktree connection tracking (KLA-96)

    /// Maps worktreeId → connectionId of the current (most recent) connection.
    /// When a new connection arrives for a worktreeId that already has one, the
    /// old connectionId is superseded. The old connection drains naturally; its
    /// close event is suppressed by the staleness check.
    private var activeConnections: [String: UUID] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]

    /// Record a new connection as current for the given worktreeId.
    /// Any previous connection for the same worktreeId is superseded — its
    /// subsequent close event will be suppressed.
    private func activateConnection(worktreeId: String) -> UUID {
        let connectionId = UUID()
        activeConnections[worktreeId] = connectionId
        return connectionId
    }

    /// Returns `true` if `connectionId` is still the active connection for
    /// `worktreeId`. Returns `false` if a newer connection has superseded it.
    private func isCurrentConnection(worktreeId: String, connectionId: UUID) -> Bool {
        activeConnections[worktreeId] == connectionId
    }

    /// Remove the tracking entry if `connectionId` is still current.
    private func deactivateConnection(worktreeId: String, connectionId: UUID) {
        if activeConnections[worktreeId] == connectionId {
            activeConnections.removeValue(forKey: worktreeId)
        }
    }

    // MARK: - Connection task lifecycle

    private func spawnConnectionHandler(
        socketFD: Int32,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) {
        let taskId = UUID()
        connectionTasks[taskId] = Task {
            await handleConnection(socketFD: socketFD, eventContinuation: eventContinuation)
            connectionTasks.removeValue(forKey: taskId)
        }
    }

    private func cancelAllConnectionTasks() {
        for task in connectionTasks.values {
            task.cancel()
        }
        connectionTasks.removeAll()
    }

    /// Long-running entry point. Returns when the listener is cancelled
    /// (the wrapping `.run` effect is cancelled on app shutdown).
    func run(
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        debugLog("MCPSocketListener.run() starting")
        do {
            try Self.ensureAppSupportDirectory()
            Self.installShimSymlink()
            try Self.unlinkStaleSocket()
            debugLog("socket unlinked, creating listener at \(Self.socketPath)")

            let listenFD = try Self.makeListeningSocket()
            debugLog("listening socket created fd=\(listenFD), entering acceptLoop")
            await acceptLoop(listenFD: listenFD, eventContinuation: eventContinuation)
            debugLog("acceptLoop returned (should never happen)")
        } catch {
            Self.logger.error("MCP listener failed to start: \(error.localizedDescription)")
            eventContinuation.yield(.errorOccurred(message: "MCP server: \(error.localizedDescription)"))
        }
    }

    // MARK: - Setup

    private static func ensureAppSupportDirectory() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
    }

    private static func unlinkStaleSocket() throws {
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }
    }

    /// Symlinks `Klausemeister.app/Contents/MacOS/klause-mcp-shim` to a
    /// stable location and registers it as an MCP server in Claude Code's
    /// user config so every `claude` instance (including meisters spawned
    /// inside tmux) knows how to reach us.
    ///
    /// Two things happen here:
    ///   1. A symlink at `~/.klausemeister/bin/klause-mcp-shim` is
    ///      (re-)created pointing to the binary inside the app bundle.
    ///   2. The `klausemeister` MCP server entry is upserted into
    ///      `~/.claude/.mcp.json` with the fully resolved shim path.
    ///      Claude Code's MCP loader does NOT expand `${HOME}` or `~` in
    ///      command strings (they're passed directly to `spawn()`), so the
    ///      app must write the real absolute path. The shim itself is safe
    ///      to register globally — it exits immediately with code 2 when
    ///      `KLAUSE_MEISTER` is not set, so non-meister claude sessions
    ///      are unaffected.
    private static func installShimSymlink() {
        let fileManager = FileManager.default
        let symlinkURL = URL(fileURLWithPath: shimSymlinkPath)
        guard let helperURL = Bundle.main.url(forAuxiliaryExecutable: "klause-mcp-shim") else {
            logger.warning("klause-mcp-shim helper not found in app bundle; symlink skipped")
            return
        }
        do {
            try fileManager.createDirectory(
                at: symlinkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Always re-create the symlink so it tracks the current app
            // bundle (e.g. after rebuilding in Xcode with a new DerivedData
            // path). Removing first is required because createSymbolicLink
            // fails if the destination already exists.
            if fileManager.fileExists(atPath: symlinkURL.path) {
                try fileManager.removeItem(at: symlinkURL)
            }
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: helperURL)
        } catch {
            logger.warning("Failed to create shim symlink: \(error.localizedDescription)")
            return
        }
        registerMCPServer()
    }

    /// Upsert the `klausemeister` MCP server into `~/.claude/.mcp.json`.
    private static func registerMCPServer() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mcpConfigURL = home.appendingPathComponent(".claude/.mcp.json")
        var root: [String: Any] = if let data = try? Data(contentsOf: mcpConfigURL),
                                     let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            parsed
        } else {
            [:]
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["command": shimSymlinkPath]
        servers["klausemeister"] = entry
        root["mcpServers"] = servers
        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: mcpConfigURL, options: .atomic)
        } catch {
            logger.warning("Failed to register MCP server in ~/.claude/.mcp.json: \(error.localizedDescription)")
        }
    }

    /// Creates a POSIX Unix-domain-socket, binds, and listens. Returns the
    /// file descriptor for the listening socket.
    ///
    /// Uses raw POSIX sockets instead of NWListener because the shim binary
    /// connects with raw `socket()`/`connect()` — NWListener with
    /// `NWParameters.tcp` adds a TCP protocol framer that never fires
    /// `newConnectionHandler` for raw clients.
    private static func makeListeningSocket() throws -> Int32 {
        let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENOENT)
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(listenFD)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { cPtr in
                for (idx, byte) in pathBytes.enumerated() {
                    cPtr[idx] = CChar(bitPattern: byte)
                }
                cPtr[pathBytes.count] = 0
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            Darwin.close(listenFD)
            throw POSIXError(.init(rawValue: err) ?? .ENOENT)
        }
        guard listen(listenFD, /* backlog */ 5) == 0 else {
            let err = errno
            Darwin.close(listenFD)
            throw POSIXError(.init(rawValue: err) ?? .ENOENT)
        }
        return listenFD
    }

    // MARK: - Accept loop

    private func acceptLoop(
        listenFD: Int32,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        debugLog("acceptLoop: listening on fd=\(listenFD)")

        // Park on the listen socket using GCD. Fires when a connection is
        // pending. Runs accept() then hands off to handleConnection.
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .global(qos: .userInitiated))
        source.setEventHandler { [self] in
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(listenFD, $0, &clientLen)
                }
            }
            guard clientFD >= 0 else { return }
            debugLog("accepted connection fd=\(clientFD)")
            Task {
                self.spawnConnectionHandler(
                    socketFD: clientFD,
                    eventContinuation: eventContinuation
                )
            }
        }
        source.resume()

        // Park until the surrounding Task is cancelled (app shutdown).
        // The continuation is resumed from the cancel handler so Swift
        // doesn't flag a leaked continuation.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                source.setCancelHandler { [self] in
                    Darwin.close(listenFD)
                    Task { self.cancelAllConnectionTasks() }
                    continuation.resume()
                }
            }
        } onCancel: {
            source.cancel()
        }
    }

    private func handleConnection(
        socketFD: Int32,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        debugLog("handleConnection entered fd=\(socketFD)")
        var worktreeId: String?
        var connectionId: UUID?
        do {
            let (helloLine, remainder) = try await SocketTransport.readHelloLine(from: socketFD)
            debugLog("hello read, remainder=\(remainder.count) bytes")
            let hello = try JSONDecoder().decode(HelloFrame.self, from: helloLine)
            guard hello.isValidMeister else {
                debugLog("invalid hello, closing")
                Darwin.close(socketFD)
                return
            }
            let wtId = hello.klauseWorktreeId
            let connId = activateConnection(worktreeId: wtId)
            worktreeId = wtId
            connectionId = connId
            debugLog("valid hello for wt=\(wtId) conn=\(connId)")

            eventContinuation.yield(.meisterHelloReceived(worktreeId: wtId))

            let transport = SocketTransport(
                socketFD: socketFD,
                logger: Logger(label: "klausemeister.mcp.transport.\(wtId)"),
                initialData: remainder
            )
            let server = await Self.makeServer(
                worktreeId: wtId,
                eventContinuation: eventContinuation
            )
            debugLog("starting MCP server")
            try await server.start(transport: transport)
            debugLog("server.start returned, waiting")
            await server.waitUntilCompleted()
            debugLog("server completed normally")

            // Only yield the close event if this connection is still the
            // current one for this worktreeId. A newer connection may have
            // superseded us while we were running (KLA-96).
            if isCurrentConnection(worktreeId: wtId, connectionId: connId) {
                eventContinuation.yield(.meisterConnectionClosed(worktreeId: wtId))
                deactivateConnection(worktreeId: wtId, connectionId: connId)
            } else {
                debugLog("suppressing stale close for wt=\(wtId) conn=\(connId)")
            }
        } catch {
            debugLog("handleConnection threw: \(error)")
            if let worktreeId, let connectionId {
                // Post-hello failure. Only report if this is still the
                // active connection — a superseded connection's errors are
                // noise from a transport we already replaced.
                if isCurrentConnection(worktreeId: worktreeId, connectionId: connectionId) {
                    eventContinuation.yield(.errorOccurred(message: "MCP connection failed: \(error.localizedDescription)"))
                    eventContinuation.yield(.meisterConnectionClosed(worktreeId: worktreeId))
                    deactivateConnection(worktreeId: worktreeId, connectionId: connectionId)
                } else {
                    debugLog("suppressing stale error for wt=\(worktreeId) conn=\(connectionId)")
                }
            } else {
                // Pre-hello failure — fd is closed by SocketTransport.deinit
                eventContinuation.yield(.errorOccurred(message: "MCP connection failed: \(error.localizedDescription)"))
            }
        }
    }
}

// MARK: - Server construction & tool dispatch

extension MCPSocketListener {
    static func makeServer(
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async -> Server {
        let server = Server(
            name: "klausemeister-mcp",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        let registeredTools = ToolCatalog.tools
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: registeredTools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await dispatchTool(
                name: params.name,
                arguments: params.arguments,
                worktreeId: worktreeId,
                eventContinuation: eventContinuation
            )
        }

        return server
    }

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate static func dispatchTool(
        name: String,
        arguments: [String: Value]?,
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async -> CallTool.Result {
        do {
            let result: ToolResult
            switch name {
            case "getNextItem":
                result = try await ToolHandlers.getNextItem(
                    worktreeId: worktreeId,
                    eventContinuation: eventContinuation
                )
            case "completeItem":
                guard let issueLinearId = arguments?["issueLinearId"]?.stringValue,
                      let nextLinearState = arguments?["nextLinearState"]?.stringValue
                else {
                    return errorResult("completeItem requires issueLinearId and nextLinearState")
                }
                result = try await ToolHandlers.completeItem(
                    issueLinearId: issueLinearId,
                    worktreeId: worktreeId,
                    nextLinearState: nextLinearState,
                    eventContinuation: eventContinuation
                )
            case "reportProgress":
                guard let issueLinearId = arguments?["issueLinearId"]?.stringValue,
                      let statusText = arguments?["statusText"]?.stringValue
                else {
                    return errorResult("reportProgress requires issueLinearId and statusText")
                }
                result = try await ToolHandlers.reportProgress(
                    issueLinearId: issueLinearId,
                    worktreeId: worktreeId,
                    statusText: statusText,
                    eventContinuation: eventContinuation
                )
            case "getStatus":
                result = try await ToolHandlers.getStatus(worktreeId: worktreeId)
            case "getProductState":
                result = try await ToolHandlers.getProductState(worktreeId: worktreeId)
            case "transition":
                guard let command = arguments?["command"]?.stringValue else {
                    return errorResult("transition requires command")
                }
                result = try await ToolHandlers.transition(
                    commandName: command,
                    worktreeId: worktreeId,
                    eventContinuation: eventContinuation
                )
            case "listWorktrees":
                result = try await ToolHandlers.listWorktrees()
            case "enqueueItem":
                guard let issueLinearId = arguments?["issueLinearId"]?.stringValue,
                      let targetWorktreeId = arguments?["targetWorktreeId"]?.stringValue
                else {
                    return errorResult("enqueueItem requires issueLinearId and targetWorktreeId")
                }
                result = try await ToolHandlers.enqueueItem(
                    issueLinearId: issueLinearId,
                    targetWorktreeId: targetWorktreeId,
                    eventContinuation: eventContinuation
                )
            default:
                return errorResult("Unknown tool: \(name)")
            }

            if result.isError {
                eventContinuation.yield(.errorOccurred(message: result.text))
            }
            return CallTool.Result(content: [.text(text: result.text, annotations: nil, _meta: nil)], isError: result.isError)
        } catch {
            let message = "MCP tool \(name) failed: \(error.localizedDescription)"
            eventContinuation.yield(.errorOccurred(message: message))
            return errorResult(message)
        }
    }

    fileprivate static func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}

// MARK: - Tool catalog (input schemas)

private enum ToolCatalog {
    nonisolated static let tools: [Tool] = [
        Tool(
            name: "getNextItem",
            // swiftlint:disable:next line_length
            description: "Claim the next inbox item from the meister's worktree queue. Marks the item as 'processing', sets the linked Linear issue to 'In Progress', and returns the full item details. Returns {\"item\":null} if the inbox is empty.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "completeItem",
            // swiftlint:disable:next line_length
            description: "Move an item from processing to outbox and set the linked Linear issue to nextLinearState. The state name (e.g. 'Todo', 'In Review', 'Done') is resolved to a team-specific Linear UUID via the local cache.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "issueLinearId": .object([
                        "type": .string("string"),
                        "description": .string("Linear UUID of the issue to complete (matches getNextItem's response)")
                    ]),
                    "nextLinearState": .object([
                        "type": .string("string"),
                        "description": .string("Target Linear workflow state name, e.g. 'Todo' / 'In Review' / 'Testing' / 'Done'")
                    ])
                ]),
                "required": .array([.string("issueLinearId"), .string("nextLinearState")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "reportProgress",
            // swiftlint:disable:next line_length
            description: "Report a brief status text for the currently processing item. The text is shown live in Klausemeister's UI for the corresponding session.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "issueLinearId": .object([
                        "type": .string("string"),
                        "description": .string("Linear UUID of the item being worked on")
                    ]),
                    "statusText": .object([
                        "type": .string("string"),
                        "description": .string("Free-form short status, e.g. 'running klause-define — exploring codebase'")
                    ])
                ]),
                "required": .array([.string("issueLinearId"), .string("statusText")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "getStatus",
            description: "Read-only snapshot of the worktree's queue: counts per position and the currently processing issue id (if any).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "getProductState",
            // swiftlint:disable:next line_length
            description: "Returns the current product state (kanban stage + queue position) for the active item in this worktree. Includes the next recommended command and all valid commands. Returns {\"state\":null} if no items are queued.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "listWorktrees",
            // swiftlint:disable:next line_length
            description: "Returns all Klausemeister-tracked worktrees with their queue state: inbox items (with sort order), processing item, outbox count, and repo identity (repoId, gitWorktreePath). Use this to discover available worktrees and their capacity. Filter by gitWorktreePath/repoId to scope to a specific repo when scheduling.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "enqueueItem",
            // swiftlint:disable:next line_length
            description: "Add an issue to a worktree's inbox queue. Appends to the end (FIFO). Idempotent — no-op if the issue is already queued on that worktree. The issue must exist in the local imported-issues cache.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "issueLinearId": .object([
                        "type": .string("string"),
                        "description": .string("Linear UUID or human identifier (e.g. KLA-136) of the issue to enqueue")
                    ]),
                    "targetWorktreeId": .object([
                        "type": .string("string"),
                        "description": .string("Klausemeister worktree ID to add the issue to")
                    ])
                ]),
                "required": .array([.string("issueLinearId"), .string("targetWorktreeId")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "transition",
            // swiftlint:disable:next line_length
            description: "Execute a workflow command to advance the product state. Validates the transition against the state machine before applying. Use getProductState first to see which commands are valid.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string("Workflow command: define, execute, review, openPR, babysit, complete, pull, push"),
                        "enum": .array([
                            .string("define"), .string("execute"), .string("review"),
                            .string("openPR"), .string("babysit"), .string("complete"),
                            .string("pull"), .string("push")
                        ])
                    ])
                ]),
                "required": .array([.string("command")]),
                "additionalProperties": .bool(false)
            ])
        )
    ]
}
