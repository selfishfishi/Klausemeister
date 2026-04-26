// Klausemeister/Dependencies/MeisterClient.swift
import Dependencies
import Foundation
import OSLog

/// Dependency client that spawns and tears down the meister Claude Code
/// process for a worktree. The meister lives inside window 0 of the worktree's
/// tmux session, identified via env vars the `klause-workflow` plugin reads
/// at session start (`KLAUSE_MEISTER=1`, `KLAUSE_WORKTREE_ID=<id>`).
///
/// `ensureRunning` is idempotent — if the backing tmux session already exists
/// it returns without re-spawning, so this is safe to call on every issue
/// assignment.
///
/// Composes `TmuxClient` via an explicit `live(tmux:)` factory (same pattern
/// as `SurfaceManager`) so that test overrides of `tmuxClient` take effect
/// without dragging a main-actor-isolated key path into the dependency
/// client's closures.
struct MeisterClient {
    nonisolated private static let log = Logger(subsystem: "com.klausemeister", category: "MeisterClient")
    var ensureRunning: @Sendable (
        _ worktreeId: String,
        _ workingDirectory: String,
        _ sessionName: String,
        _ agent: MeisterAgent
    ) async throws -> Void

    var teardown: @Sendable (_ sessionName: String) async throws -> Void
}

/// Errors thrown by the live `MeisterClient`. `LocalizedError` so the message
/// surfaces both in `os_log` (via `error.localizedDescription` at the catch
/// site in `WorktreeFeature`) and any future user-facing status surface.
enum MeisterClientError: LocalizedError {
    case agentBinaryNotFound(MeisterAgent)

    var errorDescription: String? {
        switch self {
        case .agentBinaryNotFound(.claude):
            "claude binary not found — install Claude Code from https://claude.com/claude-code"
        case .agentBinaryNotFound(.codex):
            "codex binary not found — install with `npm i -g @openai/codex` or `brew install --cask codex`"
        }
    }
}

extension MeisterClient {
    /// Resolve the meister binary command for `agent`.
    ///
    /// When the app is launched from Finder/Dock the process PATH is the
    /// stripped `/usr/bin:/bin:...` — meister binaries are almost always
    /// installed under the user's home. We probe common install locations
    /// per agent and capture an absolute path when found.
    ///
    /// `claude` falls back to the bare name on probe miss, trusting tmux's
    /// interactive shell to resolve it via the user's rc files (preserves
    /// pre-codex behavior).
    ///
    /// `codex` does NOT fall back: send-keysing a bare `codex` into a shell
    /// that cannot resolve it produces a confusing tmux session rather than
    /// an actionable error, which is exactly what the codex acceptance
    /// criteria forbid. We throw with an install hint instead.
    ///
    /// For `codex`, we also forward `KLAUSE_MEISTER` / `KLAUSE_WORKTREE_ID`
    /// to the MCP-server child via `-c mcp_servers.klausemeister.env.X=Y`
    /// inline config overrides. Codex strips inherited env when launching
    /// MCP servers (verified empirically: the codex process itself sees
    /// the vars via the tmux session env, but the shim spawned by codex's
    /// MCP launcher does not). Setting them in the per-spawn config block
    /// makes the shim see the env regardless of codex's inheritance
    /// policy. See `klause-mcp-shim/StubMCPServer.swift` for the
    /// non-meister fallback path.
    fileprivate static func resolveSpawnCommand(
        _ agent: MeisterAgent,
        worktreeId: String
    ) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [String]
        switch agent {
        case .claude:
            candidates = [
                "\(home)/.claude/local/claude",
                "\(home)/.local/bin/claude",
                "\(home)/.npm/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ]
            let resolved = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            return resolved ?? "claude"
        case .codex:
            candidates = [
                "\(home)/.codex/bin/codex",
                "\(home)/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "\(home)/.npm/bin/codex"
            ]
            guard let resolved = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw MeisterClientError.agentBinaryNotFound(.codex)
            }
            // Single-quote each `-c` argument so the user's shell parses
            // the embedded double-quoted TOML strings verbatim. WorktreeId
            // is a UUID — no shell metacharacters to worry about.
            let mcpEnvOverrides =
                " -c 'mcp_servers.klausemeister.env.KLAUSE_MEISTER=\"1\"'"
                    + " -c 'mcp_servers.klausemeister.env.KLAUSE_WORKTREE_ID=\"\(worktreeId)\"'"
            return "\(resolved) --full-auto\(mcpEnvOverrides)"
        }
    }

    static func live(tmux: TmuxClient) -> Self {
        // Foreground processes we treat as "shell waiting at a prompt" —
        // safe targets for send-keys-ing the meister command. Anything else
        // (node, claude, codex, vim, ssh, etc.) is assumed to be doing
        // something meaningful and must not be interrupted.
        let shellProcesses: Set = ["bash", "zsh", "fish", "sh", "dash", "ksh"]

        return MeisterClient(
            ensureRunning: { worktreeId, workingDirectory, sessionName, agent in
                MeisterClient.log.info("ensureRunning start wt=\(worktreeId, privacy: .public) session=\(sessionName, privacy: .public)")
                let spawnCommand: String
                do {
                    spawnCommand = try resolveSpawnCommand(agent, worktreeId: worktreeId)
                    MeisterClient.log.info("resolved agent=\(agent.rawValue, privacy: .public) command=\(spawnCommand, privacy: .public)")
                } catch {
                    MeisterClient.log.error("resolveSpawnCommand threw: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                let exists: Bool
                do {
                    exists = try await tmux.hasSession(sessionName)
                } catch {
                    MeisterClient.log.error("hasSession threw: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                MeisterClient.log.info("hasSession=\(exists, privacy: .public) for \(sessionName, privacy: .public)")
                if exists {
                    // The session exists. This can be a fresh session we
                    // just created earlier in this app run (meister already
                    // launched), a stale session from a prior app run whose
                    // claude has since exited back to a shell, or a session
                    // whose claude is still running but bound to a dead MCP
                    // socket from the previous app run.
                    //
                    // Probe window 0's foreground process. If it's a shell,
                    // claude is not present — send-keys to (re)start it.
                    // Otherwise leave the session alone; attaching will show
                    // the user whatever's running, and the grace-period
                    // fallback in WorktreeFeature will mark us .disconnected
                    // if no hello arrives (e.g., a stale claude bound to a
                    // dead socket).
                    let currentCommand: String?
                    do {
                        currentCommand = try await tmux.firstWindowCommand(sessionName)
                    } catch {
                        MeisterClient.log.error("firstWindowCommand threw: \(error.localizedDescription, privacy: .public)")
                        throw error
                    }
                    MeisterClient.log.info("firstWindowCommand=\(currentCommand ?? "<nil>", privacy: .public)")
                    if let currentCommand, shellProcesses.contains(currentCommand) {
                        MeisterClient.log.info("respawning meister into shell foreground: \(spawnCommand, privacy: .public)")
                        do {
                            try await tmux.sendKeys(sessionName, spawnCommand)
                            MeisterClient.log.info("sendKeys succeeded")
                        } catch {
                            MeisterClient.log.error("sendKeys threw: \(error.localizedDescription, privacy: .public)")
                            throw error
                        }
                    } else {
                        MeisterClient.log.info("skipping respawn (non-shell foreground)")
                    }
                    return
                }

                let env = [
                    "KLAUSE_MEISTER": "1",
                    "KLAUSE_WORKTREE_ID": worktreeId
                ]
                MeisterClient.log.info("creating new session \(sessionName, privacy: .public) at \(workingDirectory, privacy: .public)")
                try await tmux.createSession(sessionName, workingDirectory, env)

                // Target the session by name and let tmux route to the
                // newly-created first window. We deliberately do NOT pin to
                // `:0.0` because tmux `base-index 1` configurations (common
                // in user `.tmux.conf`) make window 0 non-existent — which
                // would silently fail send-keys and leave the meister
                // disconnected despite the session being up.
                MeisterClient.log.info("spawning meister via sendKeys: \(spawnCommand, privacy: .public)")
                try await tmux.sendKeys(sessionName, spawnCommand)
                MeisterClient.log.info("ensureRunning done (fresh spawn)")
            },
            teardown: { sessionName in
                try await tmux.killSession(sessionName)
            }
        )
    }
}

extension MeisterClient: DependencyKey {
    /// The real instance is built via `.live(tmux:)` and injected through
    /// `withDependencies` at `Store` creation. Accessing the default means
    /// the override never ran — fail loudly via `unimplemented(...)` so
    /// the bug surfaces instead of silently no-oping.
    nonisolated static let liveValue = MeisterClient(
        ensureRunning: unimplemented("MeisterClient.ensureRunning"),
        teardown: unimplemented("MeisterClient.teardown")
    )

    nonisolated static let testValue = MeisterClient(
        ensureRunning: unimplemented("MeisterClient.ensureRunning"),
        teardown: unimplemented("MeisterClient.teardown")
    )
}

extension DependencyValues {
    var meisterClient: MeisterClient {
        get { self[MeisterClient.self] }
        set { self[MeisterClient.self] = newValue }
    }
}
