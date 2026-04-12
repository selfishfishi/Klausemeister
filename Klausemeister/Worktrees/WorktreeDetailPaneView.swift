// Klausemeister/Worktrees/WorktreeDetailPaneView.swift
import SwiftUI

/// Presentation component rendering a worktree's terminal with an optional
/// glassmorphic board overlay showing inbox/processing/outbox queue columns.
/// The terminal is always rendered as the base layer; the board floats on top
/// with a frosted-glass treatment when `showBoardOverlay` is true.
struct WorktreeDetailPaneView: View {
    let worktree: Worktree
    var showBoardOverlay: Bool = false
    var surfaceView: SurfaceView?
    var onMarkComplete: () -> Void
    var onReturnToMeister: (String) -> Void

    var body: some View {
        ZStack {
            WorktreeTerminalTabView(
                worktree: worktree,
                surfaceView: surfaceView
            )
            .opacity(showBoardOverlay ? 0.8 : 1.0)
            .allowsHitTesting(!showBoardOverlay)

            if showBoardOverlay {
                queueColumns
                    .padding(16)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                    .padding(20)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showBoardOverlay)
    }

    private var queueColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            WorktreeQueueColumn(
                title: "Inbox",
                icon: "tray.and.arrow.down",
                issues: worktree.inbox,
                emptyText: "Drag issues here",
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Processing",
                icon: "gearshape",
                issues: worktree.processing.map { [$0] } ?? [],
                emptyText: "Nothing in progress",
                onMarkComplete: worktree.processing != nil ? onMarkComplete : nil,
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Outbox",
                icon: "tray.and.arrow.up",
                issues: worktree.outbox,
                emptyText: "Completed issues appear here",
                onReturnToMeister: onReturnToMeister
            )
        }
    }
}
