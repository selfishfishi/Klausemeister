// Klausemeister/Worktrees/Worktree+Workflow.swift
import Foundation

/// Workflow affordances derived from a `Worktree`'s current queue state.
///
/// Centralising these here keeps `SwimlaneBarRow` / `SwimlaneAdvanceButton`
/// as thin presentation components (R14): they take plain values produced
/// by this extension instead of building `ProductState` instances in the
/// view body.
extension Worktree {
    /// Best-available narration for the activity ticker shown in the sidebar.
    /// Priority: recap (persistent) → live activity → step-boundary progress.
    /// Hook tool name (`last_tool`) excluded — too terse for a headline.
    ///
    /// Used by `SwimlaneRowView` to decide whether to swap the branch/stats
    /// footer for an activity marquee. Keeping this on `Worktree` (rather
    /// than duplicating in each view) ensures both decisions agree and that
    /// cells never render a marquee AND a branch/stats footer simultaneously
    /// — doing so inflates row height inconsistently across the sidebar.
    var tickerText: String? {
        if let text = recapText, !text.isEmpty { return text }
        if let text = meisterActivityText, !text.isEmpty { return text }
        if let text = meisterStatusText, !text.isEmpty { return text }
        return nil
    }

    /// The command the meister will run next given this worktree's queue
    /// state. Prefers the processing item, falls back to the front inbox
    /// item, and is `nil` when neither resolves to a canonical stage.
    var nextWorkflowCommand: WorkflowCommand? {
        if let processing, let kanban = processing.meisterState {
            return ProductState(kanban: kanban, queue: .processing).nextCommand
        }
        if let front = inbox.first, let kanban = front.meisterState {
            return ProductState(kanban: kanban, queue: .inbox).nextCommand
        }
        return nil
    }

    /// Workflow commands that are currently valid for the processing issue.
    /// Empty when nothing is processing or when the issue has no canonical
    /// stage mapping.
    var validCommandsForActive: [WorkflowCommand] {
        guard let processing, let kanban = processing.meisterState else { return [] }
        return ProductState(kanban: kanban, queue: .processing).validCommands
    }
}

/// Target stages offered by the "Move to…" context menu on the active
/// issue. Excludes the issue's current stage so it never offers a no-op.
extension LinearIssue {
    var availableTargetStates: [MeisterState] {
        MeisterState.allCases.filter { $0 != meisterState }
    }
}
