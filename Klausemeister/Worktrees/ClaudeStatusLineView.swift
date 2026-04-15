// Klausemeister/Worktrees/ClaudeStatusLineView.swift
import SwiftUI

/// Compact one-line indicator showing the meister's Claude Code session state
/// next to `MeisterStatusDot` in sidebar rows and swimlane headers. Driven
/// purely by a `ClaudeSessionState` value; the feature layer owns updates.
/// Renders nothing (`EmptyView`) for `.offline`.
struct ClaudeStatusLineView: View {
    let state: ClaudeSessionState
    /// Free-form text from the meister's most recent `reportProgress` call.
    /// Wins over the generic label when the session is `.working`. Ignored
    /// for other states (the reducer clears it on non-working transitions).
    var text: String?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        if case .offline = state {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                StatusPulseDot(color: dotColor, pulses: isPulsing)
                Text(label)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            .lineLimit(1)
        }
    }

    private var isPulsing: Bool {
        if case .working = state { return isAnimating }
        return false
    }

    private var dotColor: Color {
        switch state {
        case .working: themeColors.accentColor
        case .idle: Color.secondary.opacity(0.6)
        case .blocked: themeColors.warningColor
        case .error: themeColors.errorColor
        case .offline: .clear
        }
    }

    private var label: String {
        switch state {
        case let .working(tool):
            // Prefer rich `reportProgress` text when present; fall back to the
            // tool name from the hook; finally fall back to the generic label.
            if let text, !text.isEmpty {
                return text
            }
            return tool ?? "Working…"
        case .idle:
            return "Idle"
        case .blocked:
            return "Needs approval"
        case .error:
            return "Error"
        case .offline:
            return ""
        }
    }
}

/// Small dot that optionally pulses. Smaller and simpler than `MeisterStatusDot`
/// because it sits alongside it rather than replacing it.
private struct StatusPulseDot: View {
    let color: Color
    let pulses: Bool

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !pulses
        )) { timeline in
            let phase = pulses
                ? 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 3.0)
                : 0.0
            let intensity = themeColors.glowIntensity

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(
                    color: color.opacity((0.3 + 0.4 * phase) * intensity),
                    radius: 2 + 2 * phase
                )
        }
    }
}
