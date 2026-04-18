import SwiftUI

/// Text with a bright band that sweeps left-to-right on a loop. The
/// band shows a single highlight color at any moment; that color
/// morphs continuously through the theme palette over time. Used on
/// the sidebar worktree name while the meister is actively working.
struct ShimmerText: View {
    let text: String
    /// The palette colors the highlight morphs through.
    let cycleColors: [Color]
    /// Base text color shown outside the bright band.
    let baseColor: Color

    /// Seconds for one full sweep across the text.
    var sweepPeriod: Double = 1.8
    /// Seconds for one full cycle through all palette colors. Longer
    /// periods make the per-sweep color feel steadier while still
    /// visibly morphing across consecutive sweeps.
    var colorCyclePeriod: Double = 18.0
    /// Width of the bright band as a fraction of the text (0→1).
    var bandWidth: Double = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweepProgress = (t / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
            let center = -bandWidth + sweepProgress * (1.0 + 2 * bandWidth)
            let highlight = interpolatedColor(at: t)

            let leftStop = clamp(center - bandWidth)
            let midStop = clamp(center)
            let rightStop = clamp(center + bandWidth)

            Text(text)
                .lineLimit(1)
                .foregroundStyle(
                    .linearGradient(
                        stops: [
                            .init(color: baseColor, location: leftStop),
                            .init(color: highlight, location: midStop),
                            .init(color: baseColor, location: rightStop)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func interpolatedColor(at elapsed: Double) -> Color {
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
