// Klausemeister/Worktrees/WorktreeDetailPaneView.swift
import SwiftUI

/// Presentation component rendering a worktree's two detail tabs: the
/// inbox/processing/outbox queue columns, and the libghostty Terminal surface
/// attached to the worktree's tmux session.
///
/// Takes plain values and closures per CLAUDE.md presentation-component rules.
struct WorktreeDetailPaneView: View {
    let worktree: Worktree
    var activeTab: WorktreeDetailTab = .queue
    var surfaceView: SurfaceView?
    var teamFor: ((_ issue: LinearIssue) -> (key: String, tint: Color)?)?
    var onMarkComplete: () -> Void
    var onReturnToMeister: (String) -> Void

    var body: some View {
        switch activeTab {
        case .queue:
            queueColumns
        case .terminal:
            WorktreeTerminalTabView(
                worktree: worktree,
                surfaceView: surfaceView
            )
        }
    }

    private var queueColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            WorktreeQueueColumn(
                title: "Inbox",
                icon: "tray.and.arrow.down",
                issues: worktree.inbox,
                emptyText: "Drag issues here",
                teamFor: teamFor,
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Processing",
                icon: "gearshape",
                issues: worktree.processing.map { [$0] } ?? [],
                emptyText: "Nothing in progress",
                teamFor: teamFor,
                onMarkComplete: worktree.processing != nil ? onMarkComplete : nil,
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Outbox",
                icon: "tray.and.arrow.up",
                issues: worktree.outbox,
                emptyText: "Completed issues appear here",
                teamFor: teamFor,
                onReturnToMeister: onReturnToMeister
            )
        }
    }
}
