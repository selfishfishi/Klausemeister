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

// swiftlint:disable:next type_body_length
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

    /// Where the status-hook script is symlinked on first launch. Codex
    /// references this absolute path in `~/.codex/config.toml` (Codex has no
    /// `${CLAUDE_PLUGIN_ROOT}` token equivalent), so the path must be stable
    /// across rebuilds and reinstalls. The symlink resolves to the copy
    /// bundled inside `Klausemeister.app/Contents/Resources` — see the
    /// `CopyStatusHook` build phase that pulls
    /// `klause-workflow/hooks/klause-status-hook.sh` into the bundle.
    static let statusHookSymlinkPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".klausemeister/hooks/klause-status-hook.sh")
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
    /// stable location and registers it as an MCP server in both Claude
    /// Code's and Codex's user config so every meister instance (spawned
    /// inside tmux) knows how to reach us, regardless of which agent the
    /// worktree uses.
    ///
    /// Five things happen here:
    ///   1. A symlink at `~/.klausemeister/bin/klause-mcp-shim` is
    ///      (re-)created pointing to the binary inside the app bundle.
    ///   2. A symlink at `~/.klausemeister/hooks/klause-status-hook.sh` is
    ///      (re-)created pointing to the script bundled inside the app's
    ///      Resources directory by the `CopyStatusHook` build phase.
    ///      Codex references this absolute path in its config.toml since
    ///      it has no `${CLAUDE_PLUGIN_ROOT}` equivalent.
    ///   3. The `klausemeister` MCP server entry is upserted into
    ///      `~/.claude/.mcp.json` with the fully resolved shim path.
    ///      Claude Code's MCP loader does NOT expand `${HOME}` or `~` in
    ///      command strings (they're passed directly to `spawn()`), so the
    ///      app must write the real absolute path.
    ///   4. The `[mcp_servers.klausemeister]` table is upserted into
    ///      `~/.codex/config.toml`. Codex spawns the shim via
    ///      `/bin/sh -c "exec ~/..."` so tilde expansion happens in the
    ///      shell.
    ///   5. The bracketed `# klausemeister-hooks-managed-block` is
    ///      upserted into `~/.codex/config.toml` with `[[hooks.X]]`
    ///      entries pointing every supported hook event at the status-hook
    ///      symlink. Claude's hooks remain wired via the plugin's
    ///      `hooks.json`; this is purely the Codex side.
    ///
    /// The shim itself is safe to register globally — when `KLAUSE_MEISTER`
    /// is not set the shim runs an MCP-protocol stub server that
    /// advertises zero tools and stays alive on stdin (see
    /// `klause-mcp-shim/StubMCPServer.swift`). Pre-stub it exited 2 and
    /// Codex surfaced "MCP startup failed: connection closed: initialize
    /// response" on every non-meister `codex` invocation. The status
    /// hook is also safe globally — it no-ops when `KLAUSE_WORKTREE_ID`
    /// is unset. Both registrations run unconditionally on every launch
    /// (idempotent and cheap) so users can switch agents per worktree
    /// without re-running setup.
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
            // path). Unconditional removal is necessary because
            // `fileExists(atPath:)` follows symlinks — a dangling symlink
            // pointing at a stale DerivedData binary would report false,
            // we'd skip the removal, and `createSymbolicLink` would then
            // fail with "file already exists".
            try? fileManager.removeItem(at: symlinkURL)
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: helperURL)
        } catch {
            logger.warning("Failed to create shim symlink: \(error.localizedDescription)")
            return
        }
        installStatusHookSymlink()
        registerClaudeMCPServer()
        registerCodexMCPServer()
        registerCodexHooks()
        installCodexPluginMarketplace()
    }

    /// Bundled klause-workflow plugin path inside the app bundle. Copied in
    /// by the `CopyKlauseWorkflowPlugin` build phase so the app ships with
    /// the slash-command + skill set Codex needs.
    static let bundledPluginPath: String? = Bundle.main.url(forResource: "klause-workflow", withExtension: nil)?.path

    /// Stable on-disk marketplace root for Codex's plugin loader. We can't
    /// hand Codex the path inside the app bundle directly: every rebuild
    /// produces a new DerivedData path, and Codex's marketplace state would
    /// drift to a stale location. Instead we set up
    /// `~/.klausemeister/plugin-marketplace/` with a symlink to the bundled
    /// plugin and re-create the symlink on every launch. Codex sees a
    /// stable path and the symlink keeps it pointed at the current build.
    static let pluginMarketplaceRoot: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".klausemeister/plugin-marketplace").path
    }()

    /// Make the klause-workflow plugin discoverable to Codex without the
    /// user running `codex plugin marketplace add` themselves. Three steps:
    ///
    ///   1. Build a stable marketplace root at
    ///      `~/.klausemeister/plugin-marketplace/` containing
    ///      `.agents/plugins/marketplace.json` and a `klause-workflow`
    ///      symlink to the bundled plugin.
    ///   2. Probe for a `codex` binary in the same locations
    ///      `MeisterClient.resolveSpawnCommand(.codex,…)` checks. If
    ///      missing, log and skip — non-codex users don't pay any cost.
    ///   3. Run `codex plugin marketplace add <root>`. The CLI is
    ///      idempotent (exits 0 with "already added" on repeat calls), so
    ///      we do this unconditionally on every launch.
    ///
    /// Errors at any step are logged and swallowed: a missing `codex`,
    /// stale config write, or unwritable home directory must never block
    /// the rest of the listener from starting.
    private static func installCodexPluginMarketplace() {
        guard let bundledPlugin = bundledPluginPath else {
            logger.info("klause-workflow plugin not bundled; codex marketplace registration skipped")
            return
        }
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: pluginMarketplaceRoot)
        let agentsPluginsDir = rootURL.appendingPathComponent(".agents/plugins")
        let marketplaceJSONURL = agentsPluginsDir.appendingPathComponent("marketplace.json")
        let pluginSymlinkURL = rootURL.appendingPathComponent("klause-workflow")
        do {
            try fileManager.createDirectory(at: agentsPluginsDir, withIntermediateDirectories: true)
            // Always re-create the plugin symlink — see `installShimSymlink`
            // for why `fileExists(atPath:)` is unsafe for symlinks.
            try? fileManager.removeItem(at: pluginSymlinkURL)
            try fileManager.createSymbolicLink(
                at: pluginSymlinkURL,
                withDestinationURL: URL(fileURLWithPath: bundledPlugin)
            )
            try canonicalMarketplaceJSON().write(
                to: marketplaceJSONURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            logger.warning("Failed to set up codex plugin marketplace: \(error.localizedDescription)")
            return
        }
        // Detached so app start doesn't wait on subprocess I/O.
        Task.detached(priority: .background) {
            await Self.runCodexMarketplaceAdd(rootPath: pluginMarketplaceRoot)
        }
    }

    private static func canonicalMarketplaceJSON() -> String {
        // Plugin source path is relative to the marketplace.json file,
        // which lives at `<root>/.agents/plugins/marketplace.json`. So
        // `../../klause-workflow` resolves to `<root>/klause-workflow`,
        // which is the symlink to the bundled plugin.
        """
        {
          "name": "klausemeister",
          "interface": {
            "displayName": "Klausemeister",
            "shortDescription": "Klausemeister workflow plugins"
          },
          "plugins": [
            {
              "name": "klause-workflow",
              "version": "0.0.1",
              "description": "Meister-loop workflow plugin for Klausemeister sessions.",
              "source": { "source": "local", "path": "../../klause-workflow" },
              "category": "development"
            }
          ]
        }
        """
    }

    private static func resolveCodexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.codex/bin/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runCodexMarketplaceAdd(rootPath: String) async {
        guard let codexPath = resolveCodexBinary() else {
            logger.info("codex binary not found; marketplace registration skipped")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["plugin", "marketplace", "add", rootPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.info("codex marketplace registered: klausemeister at \(rootPath)")
            } else {
                logger.warning("codex plugin marketplace add exited \(process.terminationStatus)")
            }
        } catch {
            logger.warning("Failed to run codex plugin marketplace add: \(error.localizedDescription)")
        }
    }

    /// Re-create `~/.klausemeister/hooks/klause-status-hook.sh` as a symlink
    /// pointing at the bundled copy. Skipped (with a warning) if the bundled
    /// script is missing — Codex meister status updates will silently no-op
    /// in that case, but the rest of the app still functions.
    private static func installStatusHookSymlink() {
        let fileManager = FileManager.default
        let symlinkURL = URL(fileURLWithPath: statusHookSymlinkPath)
        guard let scriptURL = Bundle.main.url(
            forResource: "klause-status-hook",
            withExtension: "sh"
        ) else {
            logger.warning("klause-status-hook.sh resource not found in app bundle; Codex hooks skipped")
            return
        }
        do {
            try fileManager.createDirectory(
                at: symlinkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: symlinkURL)
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: scriptURL)
        } catch {
            logger.warning("Failed to create status-hook symlink: \(error.localizedDescription)")
        }
    }

    /// Upsert the `klausemeister` MCP server into `~/.claude/.mcp.json`.
    private static func registerClaudeMCPServer() {
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

    /// Upsert `[mcp_servers.klausemeister]` into `~/.codex/config.toml`.
    ///
    /// Codex stores its MCP server config in a TOML file. We hand-roll the
    /// rewrite because the upsert only touches one named table — pulling in a
    /// TOML library would be overkill. `upsertKlausemeisterTable(in:)`
    /// preserves all other top-level keys and `[*]` tables verbatim, including
    /// any user-authored content above or below the target.
    private static func registerCodexMCPServer() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".codex")
        let configURL = configDir.appendingPathComponent("config.toml")
        do {
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning("Failed to create ~/.codex: \(error.localizedDescription)")
            return
        }
        let existing: String = if let data = try? Data(contentsOf: configURL),
                                  let text = String(data: data, encoding: .utf8)
        {
            text
        } else {
            ""
        }
        let updated = upsertKlausemeisterTable(in: existing)
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            logger.warning(
                "Failed to register MCP server in ~/.codex/config.toml: \(error.localizedDescription)"
            )
        }
    }

    /// Upsert the canonical Codex hooks block into `~/.codex/config.toml`.
    ///
    /// Codex auto-discovers `[[hooks.X]]` array-of-tables in `config.toml` and
    /// runs each entry's `command` for the corresponding event. Mapping (per
    /// KLA-210 research):
    ///
    ///   * `SessionStart`, `Stop` → `idle`
    ///   * `UserPromptSubmit`, `PreToolUse`, `PostToolUse` → `working`
    ///   * `PermissionRequest` → `blocked`
    ///
    /// `Stop` doubles as the idle proxy because Codex has no
    /// `Notification(idle_prompt)` analog. The `codex_hooks` feature flag is
    /// not set — it is stable + default-enabled (openai/codex#19012).
    ///
    /// Upsert strategy: the block is bracketed by sentinel comments and
    /// `upsertCodexHooksBlock(in:)` strips any prior block before re-appending,
    /// so user-authored `[[hooks.X]]` entries elsewhere in the file are
    /// preserved (Codex unions all matching entries from the parsed document).
    /// The status-hook script no-ops when `KLAUSE_WORKTREE_ID` is unset, so
    /// installing this globally is safe for non-meister Codex sessions.
    private static func registerCodexHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".codex")
        let configURL = configDir.appendingPathComponent("config.toml")
        do {
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning("Failed to create ~/.codex: \(error.localizedDescription)")
            return
        }
        let existing: String = if let data = try? Data(contentsOf: configURL),
                                  let text = String(data: data, encoding: .utf8)
        {
            text
        } else {
            ""
        }
        let updated = upsertCodexHooksBlock(in: existing)
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            logger.warning(
                "Failed to register Codex hooks in ~/.codex/config.toml: \(error.localizedDescription)"
            )
        }
    }

    /// Sentinel comments that mark the start and end of the canonical Codex
    /// hooks block. Anything between them is owned by the app and is
    /// rewritten verbatim on every launch.
    private static let codexHooksBeginMarker =
        "# klausemeister-hooks-managed-block:begin (do not edit — overwritten by app)"
    private static let codexHooksEndMarker = "# klausemeister-hooks-managed-block:end"

    /// Replace or append the canonical Codex hooks block in a TOML document,
    /// preserving everything else verbatim.
    ///
    /// The target block runs from the begin-marker line through the end-marker
    /// line (inclusive). The replacement block is canonical, so repeated
    /// invocations produce identical output. User-authored content above and
    /// below the block — including their own `[[hooks.X]]` entries — is left
    /// untouched.
    private static func upsertCodexHooksBlock(in existing: String) -> String {
        let canonical = canonicalCodexHooksBlock()
        let normalized = existing.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var insideBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if insideBlock {
                if trimmed == codexHooksEndMarker {
                    insideBlock = false
                }
                // else: drop — part of the old managed block
            } else if trimmed == codexHooksBeginMarker {
                insideBlock = true
            } else {
                output.append(line)
            }
        }

        // Trim trailing blank lines, then append the canonical block separated
        // by exactly one blank line so the file reads cleanly.
        while let last = output.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty
        {
            output.removeLast()
        }
        if !output.isEmpty {
            output.append("")
        }
        output.append(canonical)

        var result = output.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// Render the canonical Codex hooks block, with the absolute path to the
    /// status-hook symlink baked in.
    private static func canonicalCodexHooksBlock() -> String {
        let path = statusHookSymlinkPath
        let events = [
            "SessionStart",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PermissionRequest",
            "Stop"
        ]
        var lines: [String] = [codexHooksBeginMarker]
        for event in events {
            lines.append("[[hooks.\(event)]]")
            lines.append("[[hooks.\(event).hooks]]")
            lines.append("type = \"command\"")
            lines.append("command = \"\(path)\"")
            lines.append("")
        }
        // Drop the trailing blank we just appended after the last event so
        // the end-marker sits flush against the last entry.
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        lines.append(codexHooksEndMarker)
        return lines.joined(separator: "\n")
    }

    /// Replace or append the canonical `[mcp_servers.klausemeister]` table in
    /// a TOML document, preserving everything else verbatim.
    ///
    /// The target section runs from the `[mcp_servers.klausemeister]` header
    /// to (but not including) the next line that starts with `[` (after
    /// whitespace trimming) or EOF. The replacement block is canonical, so
    /// repeated invocations produce identical output.
    private static func upsertKlausemeisterTable(in existing: String) -> String {
        let canonical = """
        [mcp_servers.klausemeister]
        command = "/bin/sh"
        args = ["-c", "exec ~/.klausemeister/bin/klause-mcp-shim"]
        """
        let targetHeader = "[mcp_servers.klausemeister]"

        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return canonical + "\n"
        }

        let normalized = existing.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var foundTarget = false
        var insideTarget = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if insideTarget {
                if trimmed.hasPrefix("["), trimmed != targetHeader {
                    output.append(canonical)
                    output.append("")
                    output.append(line)
                    insideTarget = false
                }
                // else: drop — part of the old target block (incl. blank lines)
            } else if trimmed == targetHeader {
                insideTarget = true
                foundTarget = true
            } else {
                output.append(line)
            }
        }

        if !foundTarget || insideTarget {
            while let last = output.last,
                  last.trimmingCharacters(in: .whitespaces).isEmpty
            {
                output.removeLast()
            }
            if !output.isEmpty {
                output.append("")
            }
            output.append(canonical)
        }

        var result = output.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
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
        // Log the published tool list at every connection so a stale process
        // (running an old binary that's missing a recently added tool) is
        // diagnosable from `/tmp/klause-mcp-debug.log` without re-attaching.
        // See KLA-221 — historically we discovered tools were missing only
        // after a meister session failed to find them in ToolSearch.
        debugLog("publishing \(registeredTools.count) MCP tools: " +
            registeredTools.map(\.name).sorted().joined(separator: ","))
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
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
            case "reportActivity":
                guard let statusText = arguments?["statusText"]?.stringValue,
                      !statusText.isEmpty
                else {
                    return errorResult("reportActivity requires a non-empty statusText")
                }
                result = try await ToolHandlers.reportActivity(
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
            case "dequeueItem":
                guard let issueLinearId = arguments?["issueLinearId"]?.stringValue,
                      let targetWorktreeId = arguments?["targetWorktreeId"]?.stringValue
                else {
                    return errorResult("dequeueItem requires issueLinearId and targetWorktreeId")
                }
                result = try await ToolHandlers.dequeueItem(
                    issueLinearId: issueLinearId,
                    targetWorktreeId: targetWorktreeId,
                    eventContinuation: eventContinuation
                )
            case "saveSchedule":
                do {
                    let input = try decodeArguments(
                        ToolHandlers.SaveScheduleInput.self,
                        from: arguments
                    )
                    result = try await ToolHandlers.saveSchedule(
                        input: input,
                        eventContinuation: eventContinuation
                    )
                } catch {
                    return errorResult("saveSchedule: invalid input — \(error.localizedDescription)")
                }
            case "listSchedules":
                guard let repoId = arguments?["repoId"]?.stringValue else {
                    return errorResult("listSchedules requires repoId")
                }
                result = try await ToolHandlers.listSchedules(repoId: repoId)
            case "getSchedule":
                guard let scheduleId = arguments?["scheduleId"]?.stringValue else {
                    return errorResult("getSchedule requires scheduleId")
                }
                result = try await ToolHandlers.getSchedule(scheduleId: scheduleId)
            case "deleteSchedule":
                guard let scheduleId = arguments?["scheduleId"]?.stringValue else {
                    return errorResult("deleteSchedule requires scheduleId")
                }
                result = try await ToolHandlers.deleteSchedule(
                    scheduleId: scheduleId,
                    eventContinuation: eventContinuation
                )
            case "runSchedule":
                guard let scheduleId = arguments?["scheduleId"]?.stringValue else {
                    return errorResult("runSchedule requires scheduleId")
                }
                result = try await ToolHandlers.runSchedule(
                    scheduleId: scheduleId,
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

    /// Decode a typed input struct from the MCP `[String: Value]` argument
    /// dictionary by round-tripping through JSON. Used for tools like
    /// `saveSchedule` whose input has a nested array; the `.stringValue` /
    /// `.intValue` accessors on individual `Value` entries aren't ergonomic
    /// for deep shapes.
    fileprivate static func decodeArguments<T: Decodable>(
        _: T.Type,
        from arguments: [String: Value]?
    ) throws -> T {
        let value: Value = arguments.map(Value.object) ?? .object([:])
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Tool catalog (input schemas)

/// The catalog of tools published to MCP `ListTools` callers.
///
/// **Adding a new tool requires rebuilding and relaunching Klausemeister.app
/// before any caller session can see it.** Tool schemas are read once per
/// MCP connection (see `withMethodHandler(ListTools.self)` above) from this
/// static array, so a stale process keeps publishing whatever was compiled
/// into its binary. The shim is a transparent stdio↔socket bridge — it does
/// not cache. Symptom of a stale process: `ToolSearch` from a meister session
/// can't find the new tool name, or `gh pr view`'s tool count differs from
/// `ToolCatalog.tools.count`. Fix: rebuild (`xcodebuild`) and relaunch the app
/// (Cmd+Q the running instance, then re-open). See KLA-221.
///
/// Each new tool needs three coordinated edits:
///   1. The handler in `ToolHandlers.swift` (or `ScheduleToolHandlers.swift`).
///   2. A `case "<name>":` branch in the `dispatchTool` switch above.
///   3. A `Tool(name:description:inputSchema:)` entry in this catalog.
/// Missing #3 is the single most common reason a "newly added" tool isn't
/// callable from a meister session.
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
            name: "reportActivity",
            // swiftlint:disable:next line_length
            description: "Ambient live narration of what the meister is doing right now, shown as a scrolling ticker that fades after ~30s of silence. Use alongside (not instead of) reportProgress: reportProgress is ticket-scoped and persists for minutes at step boundaries; reportActivity is session-scoped, has no issueLinearId, and is called densely — before any tool call expected to take more than a few seconds, and whenever your focus shifts.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "statusText": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Short present-tense narration, recap style."
                        )
                    ])
                ]),
                "required": .array([.string("statusText")]),
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
            name: "dequeueItem",
            // swiftlint:disable:next line_length
            description: "Remove an issue from a worktree's inbox without claiming it. Idempotent — no-op if the issue isn't queued on that worktree. Refuses if the issue is in processing (use completeItem instead) or outbox (out of scope).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "issueLinearId": .object([
                        "type": .string("string"),
                        "description": .string("Linear UUID or human identifier (e.g. KLA-136) of the issue to remove")
                    ]),
                    "targetWorktreeId": .object([
                        "type": .string("string"),
                        "description": .string("Klausemeister worktree ID to remove the issue from")
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
        ),

        // MARK: - Saved schedules (KLA-195)

        Tool(
            name: "saveSchedule",
            // swiftlint:disable:next line_length
            description: "Persist a named schedule: a set of issues assigned to worktrees with per-worktree ordering. The schedule is saved in the 'planned' state — no queue mutation happens until runSchedule fires. Returns the new scheduleId. items[].issueLinearId and entries in items[].blockedByIssueLinearIds each accept either a Linear UUID or the human identifier (e.g. KLA-220), matching enqueueItem.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "repoId": .object([
                        "type": .string("string"),
                        "description": .string("Repository this schedule belongs to")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Human-readable schedule name (shown in sidebar pill and gantt overlay)")
                    ]),
                    "linearProjectId": .object([
                        "type": .string("string"),
                        "description": .string("Optional Linear project id the schedule was derived from")
                    ]),
                    "items": .object([
                        "type": .string("array"),
                        "description": .string("Scheduled items: issues assigned to worktrees with ordering + dependency metadata"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "worktreeId": .object(["type": .string("string")]),
                                "issueLinearId": .object([
                                    "type": .string("string"),
                                    "description": .string("Linear UUID or human identifier (e.g. KLA-220) of the issue to schedule")
                                ]),
                                "issueIdentifier": .object(["type": .string("string")]),
                                "issueTitle": .object(["type": .string("string")]),
                                "position": .object(["type": .string("integer")]),
                                "weight": .object(["type": .string("integer")]),
                                "blockedByIssueLinearIds": .object([
                                    "type": .string("array"),
                                    "items": .object([
                                        "type": .string("string"),
                                        "description": .string("Linear UUID or human identifier of an in-set blocker")
                                    ])
                                ])
                            ]),
                            "required": .array([
                                .string("worktreeId"), .string("issueLinearId"),
                                .string("issueIdentifier"), .string("issueTitle"),
                                .string("position"), .string("weight"),
                                .string("blockedByIssueLinearIds")
                            ])
                        ])
                    ])
                ]),
                "required": .array([.string("repoId"), .string("name"), .string("items")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "listSchedules",
            // swiftlint:disable:next line_length
            description: "Return a summary of every schedule for a repo, newest-first. Each entry has scheduleId, name, createdAt, runAt, totalItems, doneItems. Use getSchedule for the full item list.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "repoId": .object([
                        "type": .string("string"),
                        "description": .string("Repository id")
                    ])
                ]),
                "required": .array([.string("repoId")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "getSchedule",
            description: "Return a schedule by id, including every item with its worktree, position, weight, block list, and status.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheduleId": .object([
                        "type": .string("string"),
                        "description": .string("Schedule UUID returned by saveSchedule / listSchedules")
                    ])
                ]),
                "required": .array([.string("scheduleId")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "deleteSchedule",
            // swiftlint:disable:next line_length
            description: "Delete a schedule and all its items. Does not affect worktree queue items that were already enqueued from a prior runSchedule — those remain in their worktrees.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheduleId": .object([
                        "type": .string("string"),
                        "description": .string("Schedule UUID to delete")
                    ])
                ]),
                "required": .array([.string("scheduleId")]),
                "additionalProperties": .bool(false)
            ])
        ),
        Tool(
            name: "runSchedule",
            // swiftlint:disable:next line_length
            description: "Enqueue every item in plan order into its assigned worktree inbox, flip each item's status to queued, and stamp runAt on the schedule. Per-item failures (e.g. worktree deleted between save and run) surface in the results array without aborting the run.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheduleId": .object([
                        "type": .string("string"),
                        "description": .string("Schedule UUID to run")
                    ])
                ]),
                "required": .array([.string("scheduleId")]),
                "additionalProperties": .bool(false)
            ])
        )
    ]
}
