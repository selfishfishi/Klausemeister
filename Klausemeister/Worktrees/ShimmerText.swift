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

    /// Seconds for one full sheen sweep across the text.
    var sweepPeriod: Double = 1.8
    /// Seconds for one full cycle through the palette.
    var colorCyclePeriod: Double = 18.0
    /// Width of the sheen band as a fraction of the text (0→1).
    var bandWidth: Double = 0.25
    /// How much white to mix into the base to build the sheen color.
    var highlightBoost: Double = 0.45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let sweepProgress = (elapsed / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
            let center = -bandWidth + sweepProgress * (1.0 + 2 * bandWidth)

            let currentBase = morphedColor(at: elapsed)
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
