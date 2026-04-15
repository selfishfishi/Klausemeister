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

            ClaudeStatusLineView(
                state: worktree.claudeStatus,
                text: worktree.claudeStatusText
            )

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
                onSendSlashCommand("/klause-workflow:klause-next")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .imageScale(.small)
                    Text(nextCommand.verbLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeColors.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(
                    .regular.tint(themeColors.accentColor.opacity(0.35)).interactive(),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
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
    /// tooltip.
    ///
    /// Primary gate is `meisterStatus` — whether the tmux-hosted Claude Code
    /// process is alive. That's the reliable "can we `send-keys` right now"
    /// signal. `claudeStatus` is a secondary gate that flags known-busy
    /// states (working / blocked) so we don't interrupt mid-tool-call, but
    /// stale or offline `claudeStatus` on a running meister does NOT block —
    /// otherwise a Klausemeister restart that leaves status files frozen >60s
    /// ago (stale) would grey out every button despite the sessions being
    /// fully reachable.
    private func advanceAffordance(nextCommand _: WorkflowCommand) -> (Bool, String) {
        switch worktree.meisterStatus {
        case .none, .disconnected:
            return (false, "Meister not running")
        case .spawning:
            return (false, "Meister starting…")
        case .running:
            break
        }
        switch worktree.claudeStatus {
        case .working:
            return (false, "Meister is working…")
        case .blocked:
            return (false, "Meister is waiting for approval")
        case .idle, .error, .offline:
            return (true, "Run /klause-next in \(worktree.name)")
        }
    }
}
