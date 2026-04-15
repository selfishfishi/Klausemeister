import SwiftUI

/// Identity chip for a swimlane row: status dot + worktree name, with the
/// processing ticket identifier tucked underneath when present. The advance
/// button and queue bar live separately; this view stays single-purpose.
struct SwimlaneHeaderView: View {
    let worktree: Worktree

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                WorktreeStatusDot(
                    meisterStatus: worktree.meisterStatus,
                    claudeStatus: worktree.claudeStatus
                )
                Text(worktree.name)
                    .font(.body)
                    .lineLimit(1)
            }
            if let processing = worktree.processing {
                Text(processing.identifier)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("\(processing.identifier) · \(processing.title)")
            }
        }
    }
}
