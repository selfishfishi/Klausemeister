import SwiftUI

struct SwimlaneHeaderView: View {
    let worktree: Worktree
    /// Inject a slash command (e.g. `/klause-next`) into the worktree's
    /// tmux session. Nil hides the Advance button.
    var onSendSlashCommand: ((_ slashCommand: String) -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Text(processing.title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("\(processing.identifier) · \(processing.title)")
            } else if let branch = worktree.currentBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let stats = worktree.gitStats, !stats.isEmpty {
                GitStatsLineView(stats: stats)
            }

            ClaudeStatusLineView(
                state: worktree.claudeStatus,
                text: worktree.claudeStatusText
            )

            statusPill
            advanceButton
        }
        .padding(10)
        .frame(minWidth: 140, idealWidth: 160, alignment: .topLeading)
    }

    @ViewBuilder
    private var advanceButton: some View {
        if let nextCommand, let onSendSlashCommand {
            let (isEnabled, tooltip) = advanceAffordance(nextCommand: nextCommand)
            Button {
                onSendSlashCommand("/klause-next")
            } label: {
                Text(nextCommand.verbLabel)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isEnabled)
            .help(tooltip)
        }
    }

    /// The command the meister will run on `/klause-next` given the worktree's
    /// current queue state. Prefers the processing item; falls back to the
    /// front inbox item (`.pull`). Nil when both are empty.
    private var nextCommand: WorkflowCommand? {
        if let processing = worktree.processing, let kanban = processing.meisterState {
            return ProductState(kanban: kanban, queue: .processing).nextCommand
        }
        if let front = worktree.inbox.first, let kanban = front.meisterState {
            return ProductState(kanban: kanban, queue: .inbox).nextCommand
        }
        return nil
    }

    /// Whether the Advance button should be enabled, plus a contextual
    /// tooltip. Enable requires the meister session to be idle.
    private func advanceAffordance(nextCommand _: WorkflowCommand) -> (Bool, String) {
        switch worktree.claudeStatus {
        case .idle:
            (true, "Run /klause-next in \(worktree.name)")
        case .working:
            (false, "Meister is working…")
        case .blocked:
            (false, "Meister is waiting for approval")
        case .error:
            (false, "Meister error — check the terminal")
        case .offline:
            (false, "Meister not connected")
        }
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
