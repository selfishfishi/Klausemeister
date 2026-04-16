import AppKit
import SwiftUI

/// Attaches a native AppKit tooltip to an invisible `NSView` sibling.
/// Used where SwiftUI's `.help()` is unreliable — most notably when the
/// target view lives inside a `Button(.plain)`, whose hover interception
/// suppresses `.help()` on children. The AppKit tooltip tracking area
/// is managed by the `NSView` itself and fires independently of SwiftUI.
private struct NativeTooltipView: NSViewRepresentable {
    let tooltip: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.toolTip = tooltip
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.toolTip = tooltip
    }
}

/// Small glowing circle indicating the MCP connection status of a worktree's
/// meister. Pulses when running (`.running`); shows a static error glow when
/// disconnected; dims to a flat dot with no glow for `.none` and `.spawning`.
/// Used standalone in the Debug panel; sidebar and swimlane rows use
/// `WorktreeStatusDot` instead to fold in the Claude session signal.
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

/// Unified connectivity indicator for a worktree row. Folds the meister's MCP
/// status and the Claude session's hook-reachability into a single traffic
/// light: green when both sides are connected, yellow when exactly one is,
/// red when neither is. Hovering reveals which side is offline. "Green" is
/// about connection health, not whether Claude is actively doing work — an
/// idle-but-reachable session still counts as green.
struct WorktreeStatusDot: View {
    let meisterStatus: MeisterStatus
    let claudeStatus: ClaudeSessionState

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !isFullyHealthy
        )) { timeline in
            let period: Double = isClaudeWorking ? 1.5 : 3.0
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = isFullyHealthy
                ? 0.5 + 0.5 * sin(t * 2 * .pi / period)
                : 0.0
            let intensity = themeColors.glowIntensity
            let color = dotColor
            // When working, shift the glow between the base accent and a
            // brighter tint so the halo appears to "breathe" through
            // different shades of the theme green.
            let glowColor: Color = isClaudeWorking
                ? color.mix(with: .white, by: 0.3 * phase)
                : color

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(
                    color: glowColor.opacity(glowOpacity(phase: phase, intensity: intensity)),
                    radius: glowRadius(phase: phase)
                )
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .background(NativeTooltipView(tooltip: tooltip))
        }
    }

    private var isMeisterConnected: Bool {
        meisterStatus == .running
    }

    private var isClaudeConnected: Bool {
        if case .offline = claudeStatus {
            // The hook status file can go stale during idle stretches (>60s
            // without a tool call). But if the MCP connection is alive the
            // Claude process must be too — treat stale-but-connected as green.
            return isMeisterConnected
        }
        return true
    }

    private var connectedCount: Int {
        (isMeisterConnected ? 1 : 0) + (isClaudeConnected ? 1 : 0)
    }

    private var isFullyHealthy: Bool {
        connectedCount == 2
    }

    private var isClaudeWorking: Bool {
        guard isMeisterConnected else { return false }
        if case .working = claudeStatus { return true }
        return false
    }

    private var dotColor: Color {
        switch connectedCount {
        case 2: themeColors.accentColor
        case 1: themeColors.warningColor
        default: themeColors.errorColor
        }
    }

    private func glowOpacity(phase: Double, intensity: Double) -> Double {
        switch connectedCount {
        case 2:
            if isClaudeWorking {
                return (0.5 + 0.5 * phase) * intensity
            }
            return (0.4 + 0.4 * phase) * intensity
        case 1: return 0.5 * intensity
        default: return 0.5 * intensity
        }
    }

    private func glowRadius(phase: Double) -> CGFloat {
        if connectedCount == 2 {
            return isClaudeWorking ? 5 + 5 * phase : 3 + 3 * phase
        }
        return 3
    }

    private var tooltip: String {
        "Meister: \(meisterLabel) · Claude: \(claudeLabel)"
    }

    private var meisterLabel: String {
        switch meisterStatus {
        case .none: "not running"
        case .spawning: "starting…"
        case .running: "running"
        case .disconnected: "disconnected"
        }
    }

    private var claudeLabel: String {
        switch claudeStatus {
        case .working: "working"
        case .idle: "idle"
        case .blocked: "blocked"
        case .error: "error"
        case .offline: "offline"
        }
    }
}
