import SwiftUI

/// Advance button that sits above the queue bar in each swimlane row. Swaps
/// between Working / Blocked / Idle sub-states driven by the meister's
/// status. Renders nothing when there is no next command (inbox empty and
/// no processing item) so the content row collapses gracefully to just
/// the queue bar.
struct SwimlaneAdvanceButton: View {
    let worktree: Worktree
    var onSendSlashCommand: ((_ slashCommand: String) -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        if let nextCommand, let onSendSlashCommand {
            let (isEnabled, tooltip) = advanceAffordance(nextCommand: nextCommand)
            let isWorking: Bool = {
                guard worktree.meisterStatus == .running else { return false }
                if case .working = worktree.claudeStatus { return true }
                return false
            }()
            let isBlocked = worktree.meisterStatus == .running
                && worktree.claudeStatus == .blocked

            Group {
                if isWorking {
                    WorkingProgressPill(
                        label: nextCommand.verbLabel,
                        progressText: currentToolName,
                        accent: themeColors.accentColor
                    )
                    .help(tooltip)
                } else if isBlocked {
                    BlockedGlowView(
                        cycleColors: themeCycleColors,
                        label: nextCommand.verbLabel
                    )
                    .help(tooltip)
                } else {
                    Button {
                        onSendSlashCommand("/klause-workflow:klause-next")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play")
                                .imageScale(.small)
                            Text(nextCommand.verbLabel)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeColors.accentColor)
                    }
                    .buttonStyle(AdvanceButtonStyle(accent: themeColors.accentColor))
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.5)
                    .help(tooltip)
                }
            }
        }
    }

    /// The current tool name from the hook — shown as plain text in the
    /// working state. Activity and progress go to the marquee ticker
    /// below the processing box, not here.
    private var currentToolName: String? {
        if case let .working(tool) = worktree.claudeStatus,
           let tool, !tool.isEmpty
        {
            return tool
        }
        return nil
    }

    /// Indices 1–6 of the Everforest palette — red, green, yellow, blue,
    /// magenta, cyan. Excludes bg/fg (0 and 7) and bright/alt variants.
    private var themeCycleColors: [Color] {
        let indices = [1, 2, 3, 4, 5, 6]
        return indices.compactMap { idx in
            guard idx < themeColors.palette.count else { return nil }
            return Color(hexString: themeColors.palette[idx])
        }
    }

    /// The command the meister will run on `/klause-next` given the worktree's
    /// current queue state. Prefers the processing item; falls back to the
    /// front inbox item. Nil when both are empty.
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
    /// tooltip. Primary gate is `meisterStatus` — a disconnected process
    /// cannot receive `send-keys`. Secondary gate is `claudeStatus` for
    /// working/blocked states where interrupting mid-tool would be harmful.
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

// MARK: - Advance button style

/// Thin-bordered capsule that matches the queue-pill aesthetic. Transparent
/// at rest; fills with a subtle accent wash on press. No heavy glass effect
/// — just enough shape to read as tappable without competing with the
/// processing box or the swimlane card container.
private struct AdvanceButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(accent.opacity(configuration.isPressed ? 0.12 : 0))
            )
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                .interactiveSpring(response: 0.25, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}

// MARK: - Working-state progress pill

/// Plain text showing what the meister is doing while working. No
/// background — the comet overlay on the processing box already
/// signals "busy."
private struct WorkingProgressPill: View {
    let label: String
    var progressText: String?
    let accent: Color

    var body: some View {
        Text(progressText ?? "Working…")
            .font(.caption.weight(.medium))
            .foregroundStyle(accent)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

// MARK: - Blocked (waiting for user input) state

/// Replaces the Advance button when the meister is idle on a permission /
/// elicitation prompt (`claudeStatus == .blocked`). Same rotating comet
/// and colour cycle as the swimlane border, plus a centred `?` whose
/// glyph is also masked by the rotating gradient — so the same light
/// visibly sweeps across both the capsule border and the question mark
/// itself.
private struct BlockedGlowView: View {
    let cycleColors: [Color]
    let label: String

    private let rotationPeriod: Double = 1.5
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

        ZStack {
            // Invisible spacer matching the normal button's content so width
            // stays consistent with the idle state.
            HStack(spacing: 4) {
                Image(systemName: "play.fill").imageScale(.small)
                Text(label)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.clear.opacity(0.0001))

            // Centred question mark, lit by the same rotating gradient so the
            // comet head appears to trace through the glyph as it passes.
            rotatingGlyph(rotationDegrees: rotationDegrees, headColor: headColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            rotatingTrail(rotationDegrees: rotationDegrees, headColor: headColor)
        )
    }

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
    private func rotatingGlyph(rotationDegrees: Double, headColor: Color) -> some View {
        let stops: [Gradient.Stop] = [
            .init(color: headColor.opacity(0.35), location: 0.00),
            .init(color: headColor.opacity(0.35), location: 0.55),
            .init(color: headColor.opacity(0.65), location: 0.75),
            .init(color: headColor, location: 0.92),
            .init(color: Color.white, location: 1.00)
        ]

        AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            angle: .degrees(rotationDegrees)
        )
        .mask(
            Image(systemName: "questionmark")
                .font(.caption.weight(.bold))
        )
        .shadow(color: headColor.opacity(0.9), radius: 3)
        .blendMode(.plusLighter)
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
