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
                WorkingScanlineView(
                    cycleColors: themeCycleColors,
                    label: nextCommand.verbLabel
                )
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

    /// Indices 1–6 of the Everforest palette — red, green, yellow, blue,
    /// magenta, cyan. Excludes bg/fg (0 and 7) and bright/alt variants.
    /// Used to colour-cycle the working-state border.
    private var themeCycleColors: [Color] {
        let indices = [1, 2, 3, 4, 5, 6]
        return indices.compactMap { idx in
            guard idx < themeColors.palette.count else { return nil }
            return Color(hexString: themeColors.palette[idx])
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

/// Custom button style for the swimlane Advance button — calm at rest, with
/// a springy press animation. No continuous motion; all the "busy" visuals
/// live in `WorkingScanlineView`, rendered when the meister is processing.
private struct LiquidGlassActionButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(
                .regular
                    .tint(accent.opacity(configuration.isPressed ? 0.5 : 0.3))
                    .interactive(),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(
                .interactiveSpring(response: 0.28, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

// MARK: - Working-state animated progress

/// Replaces the Advance button while the meister is actively running a
/// tool. Transparent interior. The border is a bright comet head of an
/// AngularGradient sweeping around the capsule (~1.5s per revolution)
/// with a phosphor trail (soft halo + crisp highlight, blurred,
/// `.plusLighter` blended). The comet's colour smoothly cycles through
/// the supplied palette so the state reads as kinetic without locking to
/// a single hue.
private struct WorkingScanlineView: View {
    /// Palette the comet head cycles through, in display order. Typically
    /// the theme's main colours (red/green/yellow/blue/magenta/cyan),
    /// excluding background and foreground.
    let cycleColors: [Color]
    let label: String

    /// Seconds per full revolution of the comet head.
    private let rotationPeriod: Double = 1.5
    /// Seconds per full sweep through every colour in `cycleColors`.
    private let colorCyclePeriod: Double = 6.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            animatedBody(time: timeline.date)
        }
    }

    @ViewBuilder
    private func animatedBody(time: Date) -> some View {
        let elapsed = time.timeIntervalSinceReferenceDate
        let rotationDegrees = (elapsed / rotationPeriod)
            .truncatingRemainder(dividingBy: 1) * 360
        let headColor = interpolatedColor(at: elapsed)

        HStack(spacing: 4) {
            Image(systemName: "play.fill").imageScale(.small)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.clear.opacity(0.0001))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            rotatingTrail(rotationDegrees: rotationDegrees, headColor: headColor)
        )
    }

    /// Linearly interpolate between adjacent `cycleColors` entries based on
    /// elapsed time, wrapping at the end so the cycle loops.
    private func interpolatedColor(at elapsed: Double) -> Color {
        guard !cycleColors.isEmpty else { return .white }
        guard cycleColors.count > 1 else { return cycleColors[0] }

        let count = Double(cycleColors.count)
        let progress = ((elapsed / colorCyclePeriod)
            .truncatingRemainder(dividingBy: 1)) * count
        let index = Int(progress) % cycleColors.count
        let nextIndex = (index + 1) % cycleColors.count
        let fraction = progress - Double(index)
        return cycleColors[index].mix(with: cycleColors[nextIndex], by: fraction)
    }

    @ViewBuilder
    private func rotatingTrail(rotationDegrees: Double, headColor: Color) -> some View {
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0.00),
            .init(color: .clear, location: 0.50),
            .init(color: headColor.opacity(0.25), location: 0.68),
            .init(color: headColor.opacity(0.70), location: 0.82),
            .init(color: headColor, location: 0.94),
            .init(color: Color.white, location: 1.00)
        ]

        ZStack {
            Capsule()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: stops),
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 3.2
                )
                .blur(radius: 3.5)

            Capsule()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: stops),
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 1.2
                )
                .blur(radius: 0.6)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
