import SwiftUI

/// Text whose color gradually cycles through the theme palette, with
/// a sheen band sweeping left-to-right on a loop. The sheen is always
/// a lighter variant of whatever the text color is at that instant —
/// the shimmer is the text itself brightening, not a different color.
/// Used on the sidebar worktree name while the meister is actively
/// working.
struct ShimmerText: View {
    let text: String
    /// Colors the text gradually morphs between over time.
    let cycleColors: [Color]
    /// Fallback text color when `cycleColors` is empty.
    let baseColor: Color
    /// Per-instance phase desync seed. Two instances with different seeds
    /// will be at different sweep positions and palette colors at the same
    /// wall-clock moment, so a row of shimmers doesn't pulse in lockstep.
    /// Pass the worktree id (or any stable string) to keep each row at the
    /// same offset across renders. Empty string falls back to no offset.
    var phaseSeed: String = ""

    /// Seconds for one full sheen sweep across the text.
    var sweepPeriod: Double = 1.8
    /// Seconds for one full cycle through the palette.
    var colorCyclePeriod: Double = 18.0
    /// Width of the sheen band as a fraction of the text (0→1).
    var bandWidth: Double = 0.25
    /// How much white to mix into the base to build the sheen color.
    var highlightBoost: Double = 0.45

    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        // 15 Hz = 27 frames per 1.8 s sheen sweep — visually smooth for a
        // gradient shimmer, and halves the body-rebuild cost vs 30 Hz. With
        // N worktrees running a meister, each renders its own ShimmerText,
        // so per-instance savings scale linearly. Paused when the window is
        // backgrounded so sidebar shimmers go quiet for a minimised app.
        TimelineView(.animation(
            minimumInterval: 1.0 / 15.0,
            paused: activeState == .inactive
        )) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let sweepElapsed = now - sweepOffset
            let colorElapsed = now - colorOffset
            let sweepProgress = (sweepElapsed / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
            let normalizedSweep = sweepProgress < 0 ? sweepProgress + 1 : sweepProgress
            let center = -bandWidth + normalizedSweep * (1.0 + 2 * bandWidth)

            let currentBase = morphedColor(at: colorElapsed)
            let highlight = currentBase.mix(with: .white, by: highlightBoost)

            let leftStop = clamp(center - bandWidth)
            let midStop = clamp(center)
            let rightStop = clamp(center + bandWidth)

            Text(text)
                .lineLimit(1)
                .foregroundStyle(
                    .linearGradient(
                        stops: [
                            .init(color: currentBase, location: leftStop),
                            .init(color: highlight, location: midStop),
                            .init(color: currentBase, location: rightStop)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    /// Stable per-seed sweep offset in `[0, sweepPeriod)`.
    private var sweepOffset: Double {
        guard !phaseSeed.isEmpty else { return 0 }
        let hash = phaseSeed.utf8.reduce(0) { $0 &+ Int($1) }
        return Double(hash % 1000) / 1000.0 * sweepPeriod
    }

    /// Stable per-seed color-cycle offset in `[0, colorCyclePeriod)`.
    /// Uses a different mix of the hash so it isn't perfectly correlated
    /// with `sweepOffset`.
    private var colorOffset: Double {
        guard !phaseSeed.isEmpty else { return 0 }
        let hash = phaseSeed.utf8.reduce(7) { ($0 &* 31) &+ Int($1) }
        return Double(abs(hash) % 1000) / 1000.0 * colorCyclePeriod
    }

    private func morphedColor(at elapsed: Double) -> Color {
        guard !cycleColors.isEmpty else { return baseColor }
        guard cycleColors.count > 1 else { return cycleColors[0] }
        let count = Double(cycleColors.count)
        let raw = (elapsed / colorCyclePeriod).truncatingRemainder(dividingBy: 1)
        let normalized = raw < 0 ? raw + 1 : raw
        let progress = normalized * count
        let index = Int(progress) % cycleColors.count
        let nextIndex = (index + 1) % cycleColors.count
        let fraction = progress - Double(Int(progress))
        // Smoothstep for a gentler morph between adjacent colors.
        let eased = fraction * fraction * (3 - 2 * fraction)
        return cycleColors[index].mix(with: cycleColors[nextIndex], by: eased)
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
