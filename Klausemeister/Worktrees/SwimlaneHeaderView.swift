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
            let isWorking: Bool = {
                guard worktree.meisterStatus == .running else { return false }
                if case .working = worktree.claudeStatus { return true }
                return false
            }()

            if isWorking {
                WorkingScanlineView(accent: themeColors.accentColor, label: nextCommand.verbLabel)
                    .help(tooltip)
            } else {
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
                }
                .buttonStyle(LiquidGlassActionButtonStyle(accent: themeColors.accentColor))
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
                .help(tooltip)
            }
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

// MARK: - Liquid Glass button style

/// Custom button style for the swimlane Advance button. Wraps the label in a
/// Liquid Glass capsule that shifts tint + scales slightly on press for
/// tactile feedback. `.interactive()` on the glass handles the native
/// lensing response; this style adds the extra motion polish.
private struct LiquidGlassActionButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(
                .regular
                    .tint(accent.opacity(configuration.isPressed ? 0.55 : 0.35))
                    .interactive(),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Working-state animated progress

/// Replaces the Advance button while the meister is actively running a
/// tool. The capsule keeps its Liquid Glass material but the label is
/// swapped for a breathing scanline — a bright accent-tinted band sweeps
/// left-to-right through the glass while the tint opacity pulses
/// sinusoidally. Communicates "busy" without stealing visual weight.
private struct WorkingScanlineView: View {
    let accent: Color
    let label: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweepPeriod = 1.6
            let pulsePeriod = 2.4
            let sweepPhase = (t.truncatingRemainder(dividingBy: sweepPeriod)) / sweepPeriod
            let pulsePhase = 0.5 + 0.5 * sin(t * 2 * .pi / pulsePeriod)
            let tintOpacity = 0.25 + 0.2 * pulsePhase

            // Keep layout width identical to the normal button by rendering
            // the same label content, but hide it visually so only the
            // scanline reads.
            HStack(spacing: 4) {
                Image(systemName: "play.fill").imageScale(.small)
                Text(label)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent.opacity(0.0001)) // measurable but invisible
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                GeometryReader { proxy in
                    let bandWidth: CGFloat = max(proxy.size.width * 0.35, 18)
                    let travel = proxy.size.width + bandWidth
                    let offsetX = CGFloat(sweepPhase) * travel - bandWidth / 2

                    LinearGradient(
                        colors: [
                            .clear,
                            accent.opacity(0.85),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: offsetX)
                    .allowsHitTesting(false)
                }
                .clipShape(Capsule())
            )
            .glassEffect(
                .regular.tint(accent.opacity(tintOpacity)),
                in: Capsule()
            )
        }
    }
}
