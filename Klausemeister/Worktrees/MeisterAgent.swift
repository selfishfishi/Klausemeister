// Klausemeister/Worktrees/MeisterAgent.swift
import Foundation

/// Which agent runs as the meister for a worktree. Persisted on the
/// `worktrees` row (see migration v16) so the choice survives restarts
/// and can differ per worktree.
enum MeisterAgent: String, Codable, CaseIterable {
    case claude
    case codex
}

extension MeisterAgent {
    /// Prefix for app-side slash commands sent to this agent's meister via
    /// `tmux send-keys`. Claude resolves plugin commands as
    /// `/klause-workflow:<name>`; Codex doesn't bundle plugin slash
    /// commands (KLA-215) so it uses the bare `/<name>` form (KLA-216).
    var slashCommandPrefix: String {
        switch self {
        case .claude: "/klause-workflow:"
        case .codex: "/"
        }
    }
}
