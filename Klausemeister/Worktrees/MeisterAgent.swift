// Klausemeister/Worktrees/MeisterAgent.swift
import Foundation

/// Which agent runs as the meister for a worktree. Persisted on the
/// `worktrees` row (see migration v16) so the choice survives restarts
/// and can differ per worktree. Behavior branching on this value
/// (process spawn, slash-command dispatch) lands in follow-up tickets;
/// today this is a typed field with no behavioral side effects.
enum MeisterAgent: String, Codable, CaseIterable {
    case claude
    case codex
}
