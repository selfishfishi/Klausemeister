// Klausemeister/Dependencies/MeisterClient.swift
import Dependencies
import Foundation

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

        return MeisterClient(
            ensureRunning: { worktreeId, workingDirectory, sessionName in
                // Short-circuit if the backing session already exists. This
                // is the "reuse" branch — the meister inside that session is
                // either already running or will reconnect to the socket on
                // its own when the app relaunches.
                if try await tmux.hasSession(sessionName) {
                    return
                }

                let env = [
                    "KLAUSE_MEISTER": "1",
                    "KLAUSE_WORKTREE_ID": worktreeId
                ]
                try await tmux.createSession(sessionName, workingDirectory, env)

                // Target the session by name and let tmux route to the
                // newly-created first window. We deliberately do NOT pin to
                // `:0.0` because tmux `base-index 1` configurations (common
                // in user `.tmux.conf`) make window 0 non-existent — which
                // would silently fail send-keys and leave the meister
                // disconnected despite the session being up.
                try await tmux.sendKeys("=\(sessionName)", claudeCommand)
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
