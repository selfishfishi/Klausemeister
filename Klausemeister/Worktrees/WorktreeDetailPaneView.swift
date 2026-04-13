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
    var teamFor: ((_ issue: LinearIssue) -> (key: String, tint: Color)?)?
    var onMarkComplete: () -> Void
    var onReturnToMeister: (String) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        ZStack {
            WorktreeTerminalTabView(
                worktree: worktree,
                surfaceView: surfaceView
            )
            .blur(radius: showBoardOverlay ? 10 : 0)
            .opacity(showBoardOverlay ? 0.8 : 1.0)
            .allowsHitTesting(!showBoardOverlay)

            if showBoardOverlay {
                queueColumns
                    .padding(16)
                    .background(
                        Color(hexString: themeColors.background).opacity(0.5),
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
