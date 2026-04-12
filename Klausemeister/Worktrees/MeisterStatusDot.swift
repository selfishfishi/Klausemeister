import SwiftUI

/// Small glowing circle indicating the MCP connection status of a worktree's
/// meister. Pulses when running (`.running`); shows a static error glow when
/// disconnected; dims to a flat dot with no glow for `.none` and `.spawning`.
struct MeisterStatusDot: View {
    let status: MeisterStatus

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: status != .running || !isAnimating
        )) { timeline in
            let phase = (status == .running && isAnimating)
                ? pulsePhase(date: timeline.date, period: 3.0)
                : 0.0
            let intensity = themeColors.glowIntensity
            let color = dotColor

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(
                    color: color.opacity(glowOpacity(phase: phase, intensity: intensity)),
                    radius: glowRadius(phase: phase)
                )
        }
    }

    private var dotColor: Color {
        switch status {
        case .running:
            themeColors.accentColor
        case .disconnected:
            themeColors.errorColor
        case .none, .spawning:
            Color.secondary.opacity(0.4)
        }
    }

    private func glowOpacity(phase: Double, intensity: Double) -> Double {
        switch status {
        case .running:
            (0.4 + 0.4 * phase) * intensity
        case .disconnected:
            0.5 * intensity
        case .none, .spawning:
            0
        }
    }

    private func glowRadius(phase: Double) -> CGFloat {
        switch status {
        case .running:
            3 + 3 * phase
        case .disconnected:
            3
        case .none, .spawning:
            0
        }
    }

    private func pulsePhase(date: Date, period: Double) -> Double {
        0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
    }
}
