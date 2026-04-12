import SwiftUI

struct SwimlaneRowView: View {
    let worktree: Worktree
    /// Unique per-row tint resolved by the parent from the theme's swimlane
    /// palette. Used as the glass container tint so each lane reads as its
    /// own surface. The 30fps active pulse still uses `accentColor` so all
    /// "work is happening" cues read the same across rows.
    let tint: Color
    let onDelete: () -> Void
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDropToInbox: ((_ issueId: String) -> Void)?
    var onDropToProcessing: ((_ issueId: String) -> Void)?
    var onDropToOutbox: ((_ issueId: String) -> Void)?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !worktree.isActive || !isAnimating
        )) { timeline in
            let phase = worktree.isActive
                ? pulsePhase(date: timeline.date, period: 2.0)
                : 0.0
            let intensity = themeColors.glowIntensity

            rowContent
                .overlay {
                    RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                        .stroke(
                            themeColors.accentColor.opacity(
                                worktree.isActive ? (0.3 + 0.5 * phase) * intensity : 0
                            ),
                            lineWidth: 1.5
                        )
                }
                .shadow(
                    color: themeColors.accentColor.opacity(
                        worktree.isActive ? (0.15 + 0.25 * phase) * intensity : 0
                    ),
                    radius: worktree.isActive ? 4 + 8 * phase : 0
                )
        }
        .animation(.easeInOut(duration: 0.3), value: worktree.isActive)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            SwimlaneHeaderView(
                worktree: worktree,
                onDelete: onDelete
            )

            SwimlaneQueueView(
                role: .inbox,
                issues: worktree.inbox,
                onReturnToMeister: onReturnToMeister,
                onDrop: onDropToInbox
            )

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneProcessingZoneView(
                issue: worktree.processing,
                onMarkComplete: onMarkComplete,
                onReturnToMeister: onReturnToMeister,
                onDrop: onDropToProcessing
            )

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneQueueView(
                role: .outbox,
                issues: worktree.outbox,
                onReturnToMeister: onReturnToMeister,
                onDrop: onDropToOutbox
            )
        }
        .padding(10)
        .glassPanel(tint: tint, cornerRadius: swimlaneGlassCornerRadius)
    }

    private func pulsePhase(date: Date, period: Double) -> Double {
        0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
    }
}
