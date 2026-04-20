// Klausemeister/Worktrees/WorktreeMenuEntry.swift
import Foundation

/// Lightweight DTO that presentation components use to render the
/// "Move to Worktree" context menu in the kanban board. Exposes only
/// the fields the menu actually reads — id, name, inbox size, and repo
/// grouping metadata — so SwiftUI can skip menu rebuilds when unrelated
/// fields on the full `Worktree` (Claude activity text, git stats, meister
/// status) change. Fixes the KLA-62 coupling that made `KanbanIssueCardView`
/// re-evaluate on every meister tick.
struct WorktreeMenuEntry: Equatable, Identifiable {
    let id: String
    let name: String
    let inboxCount: Int
    let repoId: String?
    let repoName: String?
}
