import SwiftUI

struct SwimlaneHeaderView: View {
    let worktree: Worktree
    let onDelete: () -> Void
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse" : "Expand")
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                }
                Text(worktree.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("Delete worktree", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let branch = worktree.currentBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

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
