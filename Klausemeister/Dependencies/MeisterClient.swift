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
        _ sessionName: String
    ) async throws -> Void

    var teardown: @Sendable (_ sessionName: String) async throws -> Void
}

extension MeisterClient {
    static func live(tmux: TmuxClient) -> Self {
        // Resolve the `claude` binary once at construction time. When the app
        // is launched from Finder/Dock the process PATH is the stripped
        // `/usr/bin:/bin:...` — `claude` is almost always installed under
        // the user's home. We probe common install locations and capture an
        // absolute path when found. If none match we fall back to the bare
        // name, trusting tmux's interactive shell to resolve it via the
        // user's rc files.
        let claudeCommand: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let candidates = [
                "\(home)/.claude/local/claude",
                "\(home)/.local/bin/claude",
                "\(home)/.npm/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
        }()

        // Foreground processes we treat as "shell waiting at a prompt" —
        // safe targets for send-keys-ing the claude command. Anything else
        // (node, claude, vim, ssh, etc.) is assumed to be doing something
        // meaningful and must not be interrupted.
        let shellProcesses: Set = ["bash", "zsh", "fish", "sh", "dash", "ksh"]

        return MeisterClient(
            ensureRunning: { worktreeId, workingDirectory, sessionName in
                MeisterClient.log.info("ensureRunning start wt=\(worktreeId, privacy: .public) session=\(sessionName, privacy: .public)")
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
                        MeisterClient.log.info("respawning claude into shell foreground: \(claudeCommand, privacy: .public)")
                        do {
                            try await tmux.sendKeys(sessionName, claudeCommand)
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
                MeisterClient.log.info("spawning claude via sendKeys: \(claudeCommand, privacy: .public)")
                try await tmux.sendKeys(sessionName, claudeCommand)
                MeisterClient.log.info("ensureRunning done (fresh spawn)")
            },
            teardown: { sessionName in
                try await tmux.killSession(sessionName)
            }
        )
    }
}

extension MeisterClient: DependencyKey {
    /// No-op stub. The real client is injected via `withDependencies` at
    /// `KlausemeisterApp.init` using `.live(tmux:)`, mirroring how
    /// `SurfaceManager` is composed.
    nonisolated static let liveValue = MeisterClient(
        ensureRunning: { _, _, _ in },
        teardown: { _ in }
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
