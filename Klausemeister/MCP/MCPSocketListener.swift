// Klausemeister/MCP/MCPSocketListener.swift
import Foundation
import Logging
import MCP
import Network

/// Owns the Unix-domain-socket listener for the in-process MCP server.
///
/// `MCPSocketListener.run(eventContinuation:)` is called once at app start by
/// `MCPServerClient.liveValue.start`. It:
///   1. Installs the shim symlink so the plugin can find the helper.
///   2. Unlinks any stale socket file from a previous app run.
///   3. Binds an `NWListener` to the socket path and accepts connections.
///   4. For each connection: reads the `HelloFrame`, validates the master
///      identity, then constructs a per-connection `SocketTransport` + MCP
///      `Server` with tool handlers closing over the worktree id.
///   5. Yields any errors encountered to `eventContinuation` so they reach
///      `StatusBarFeature` via the `AppFeature` bridge.
///
/// The function returns only when the underlying `.run` effect is cancelled
/// (i.e. when the app is shutting down).
enum MCPSocketListener {
    /// Hard-coded socket path. Klausemeister assumes a single instance per
    /// machine; if you ever run two copies they will fight for this path.
    static let socketPath: String = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Klausemeister")
        return appSupport.appendingPathComponent("klause.sock").path
    }()

    /// Where the shim helper is symlinked on first launch so the plugin's
    /// `mcp.json` can reference it without knowing where the .app is installed.
    static let shimSymlinkPath: String = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Klausemeister")
            .appendingPathComponent("bin")
        return appSupport.appendingPathComponent("klause-mcp-shim").path
    }()

    private static let logger = Logger(label: "klausemeister.mcp.listener")

    /// Long-running entry point. Returns when the listener is cancelled
    /// (the wrapping `.run` effect is cancelled on app shutdown).
    static func run(
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        do {
            try ensureAppSupportDirectory()
            installShimSymlink()
            try unlinkStaleSocket()

            let listener = try makeListener()
            await acceptLoop(listener: listener, eventContinuation: eventContinuation)
        } catch {
            logger.error("MCP listener failed to start: \(error.localizedDescription)")
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

    /// Symlinks `Klausemeister.app/Contents/Helpers/klause-mcp-shim` to a
    /// stable location so the workflow plugin's `mcp.json` can refer to a
    /// fixed path. No-op if the symlink already exists and points anywhere.
    private static func installShimSymlink() {
        let fileManager = FileManager.default
        let symlinkURL = URL(fileURLWithPath: shimSymlinkPath)
        guard !fileManager.fileExists(atPath: symlinkURL.path) else { return }
        guard let helperURL = Bundle.main.url(forAuxiliaryExecutable: "klause-mcp-shim") else {
            logger.warning("klause-mcp-shim helper not found in app bundle; symlink skipped")
            return
        }
        do {
            try fileManager.createDirectory(
                at: symlinkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: helperURL)
        } catch {
            logger.warning("Failed to create shim symlink: \(error.localizedDescription)")
        }
    }

    private static func makeListener() throws -> NWListener {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters.tcp // any stream-based params; the unix endpoint forces UDS
        parameters.requiredLocalEndpoint = endpoint
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        return try NWListener(using: parameters)
    }

    // MARK: - Accept loop

    private static func acceptLoop(
        listener: NWListener,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        let queue = DispatchQueue(label: "klausemeister.mcp.listener")

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Task.detached {
                await handleConnection(
                    connection,
                    eventContinuation: eventContinuation
                )
            }
        }

        listener.start(queue: queue)

        // Park until the surrounding Task is cancelled (app shutdown).
        await withTaskCancellationHandler {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                // Never resumed — cancellation handler tears down the listener.
                // The continuation is intentionally leaked; Swift Concurrency
                // cleans it up when the enclosing Task is cancelled.
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private static func handleConnection(
        _ connection: NWConnection,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async {
        do {
            let (helloLine, _) = try await SocketTransport.readHelloLine(from: connection)
            let hello = try JSONDecoder().decode(HelloFrame.self, from: helloLine)
            guard hello.isValidPrimary else {
                connection.cancel()
                return
            }

            let transport = SocketTransport(
                connection: connection,
                logger: Logger(label: "klausemeister.mcp.transport.\(hello.klauseWorktreeId)")
            )
            let server = await makeServer(
                worktreeId: hello.klauseWorktreeId,
                eventContinuation: eventContinuation
            )
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            connection.cancel()
            eventContinuation.yield(.errorOccurred(message: "MCP connection failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Server construction

    private static func makeServer(
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

    // MARK: - Tool dispatch

    private static func dispatchTool(
        name: String,
        arguments: [String: Value]?,
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async -> CallTool.Result {
        do {
            let result: ToolResult
            switch name {
            case "getNextItem":
                result = try await ToolHandlers.getNextItem(worktreeId: worktreeId)
            case "completeItem":
                guard let issueLinearId = arguments?["issueLinearId"]?.stringValue,
                      let nextLinearState = arguments?["nextLinearState"]?.stringValue
                else {
                    return errorResult("completeItem requires issueLinearId and nextLinearState")
                }
                result = try await ToolHandlers.completeItem(
                    issueLinearId: issueLinearId,
                    worktreeId: worktreeId,
                    nextLinearState: nextLinearState
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

    private static func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}

// MARK: - Tool catalog (input schemas)

private enum ToolCatalog {
    static let tools: [Tool] = [
        Tool(
            name: "getNextItem",
            // swiftlint:disable:next line_length
            description: "Claim the next inbox item from the master's worktree queue. Marks the item as 'processing', sets the linked Linear issue to 'In Progress', and returns the full item details. Returns {\"item\":null} if the inbox is empty.",
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
                        "description": .string("Free-form short status, e.g. 'running klause-spec — exploring codebase'")
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
        )
    ]
}
