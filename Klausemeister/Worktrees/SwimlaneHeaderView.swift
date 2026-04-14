import SwiftUI

struct SwimlaneHeaderView: View {
    let worktree: Worktree

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MeisterStatusDot(status: worktree.meisterStatus)
                Text(worktree.name)
                    .font(.body)
                    .lineLimit(1)
            }

            if let branch = worktree.currentBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let stats = worktree.gitStats, !stats.isEmpty {
                GitStatsLineView(stats: stats)
            }

            ClaudeStatusLineView(state: worktree.claudeStatus)

            statusPill
        }
        .padding(10)
        .frame(minWidth: 140, idealWidth: 160, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusPill: some View {
        let (label, tint) = statusLabelAndTint
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private var statusLabelAndTint: (String, Color) {
        if worktree.processing != nil {
            ("ACTIVE", themeColors.accentColor)
        } else if !worktree.inbox.isEmpty {
            ("QUEUED", themeColors.warningColor)
        } else {
            ("IDLE", .secondary)
        }
    }
}
