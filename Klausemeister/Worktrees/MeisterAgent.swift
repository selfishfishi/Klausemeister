// Klausemeister/Worktrees/MeisterAgent.swift
import Foundation

/// Which agent runs as the meister for a worktree. Persisted on the
/// `worktrees` row (see migration v16) so the choice survives restarts
/// and can differ per worktree.
enum MeisterAgent: String, Codable, CaseIterable {
    case claude
    case codex
}

enum MeisterCommand: Equatable, Hashable {
    case next
    case workflow(WorkflowCommand)
}

extension MeisterAgent {
    /// Agent-facing command text sent to a meister via `tmux send-keys`.
    /// Claude resolves plugin commands as slash commands; Codex invokes
    /// installed skills through its `$` command palette syntax.
    func commandText(for command: MeisterCommand) -> String? {
        switch self {
        case .claude:
            guard let name = command.claudeSlashCommandName else { return nil }
            return "/klause-workflow:\(name)"
        case .codex:
            guard let name = command.codexSkillName else { return nil }
            return "$\(name)"
        }
    }
}

private extension MeisterCommand {
    var claudeSlashCommandName: String? {
        switch self {
        case .next:
            "klause-next"
        case let .workflow(command):
            command.claudeSlashCommandName
        }
    }

    var codexSkillName: String? {
        switch self {
        case .next:
            "Klausemeister Next"
        case let .workflow(command):
            command.codexSkillName
        }
    }
}
