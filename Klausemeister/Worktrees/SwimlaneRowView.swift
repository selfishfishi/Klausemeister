import SwiftUI

struct SwimlaneRowView: View {
    let worktree: Worktree
    let onDelete: () -> Void
    var onReturnToMeister: ((_ issueId: String) -> Void)?

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
                    RoundedRectangle(cornerRadius: 10)
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
        HStack(alignment: .top, spacing: 0) {
            SwimlaneHeaderView(worktree: worktree, onDelete: onDelete)

            Divider()

            SwimlaneQueueView(
                role: .inbox,
                issues: worktree.inbox,
                onReturnToMeister: onReturnToMeister
            )

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneProcessingZoneView(
                issue: worktree.processing,
                onReturnToMeister: onReturnToMeister
            )

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneQueueView(
                role: .outbox,
                issues: worktree.outbox,
                onReturnToMeister: onReturnToMeister
            )
        }
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pulsePhase(date: Date, period: Double) -> Double {
        0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
    }
}
