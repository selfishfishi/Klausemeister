import SwiftUI

struct SwimlaneRowView: View {
    let worktree: Worktree
    let onDelete: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SwimlaneHeaderView(worktree: worktree, onDelete: onDelete)

            Divider()

            SwimlaneQueueView(role: .inbox, issues: worktree.inbox)

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneProcessingZoneView(issue: worktree.processing)

            SwimlaneConnectorShape(isActive: worktree.isActive)

            SwimlaneQueueView(role: .outbox, issues: worktree.outbox)
        }
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    themeColors.accentColor.opacity(worktree.isActive ? 0.6 : 0),
                    lineWidth: 1.5
                )
        }
        .shadow(
            color: themeColors.accentColor.opacity(worktree.isActive ? 0.25 : 0),
            radius: 8
        )
        .animation(.easeInOut(duration: 0.3), value: worktree.isActive)
    }
}
