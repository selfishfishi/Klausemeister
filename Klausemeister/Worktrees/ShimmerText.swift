import SwiftUI

/// Text with a bright band that sweeps left-to-right on a loop,
/// cycling through the theme palette colors as it goes. Used on the
/// sidebar worktree name while the meister is actively working.
struct ShimmerText: View {
    let text: String
    /// The palette colors to cycle through (e.g. Everforest indices 1–6).
    let cycleColors: [Color]
    /// Base text color shown outside the bright band.
    let baseColor: Color

    /// Seconds for one full sweep across the text.
    var sweepPeriod: Double = 2.0
    /// Seconds for one full cycle through all palette colors.
    var colorCyclePeriod: Double = 6.0
    /// Width of the bright band as a fraction of the text (0→1).
    var bandWidth: Double = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweepProgress = (t / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
            let center = -bandWidth + sweepProgress * (1.0 + 2 * bandWidth)
            let highlight = interpolatedColor(at: t)

            // Clamp all three stops to [0, 1] so they stay ordered even
            // while the band enters from or exits past the text edges.
            let lo = max(0, min(1, center - bandWidth))
            let mid = max(0, min(1, center))
            let hi = max(0, min(1, center + bandWidth))

            Text(text)
                .lineLimit(1)
                .foregroundStyle(
                    .linearGradient(
                        stops: [
                            .init(color: baseColor, location: lo),
                            .init(color: highlight, location: mid),
                            .init(color: baseColor, location: hi)
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
        let progress = (raw < 0 ? raw + 1 : raw) * count
        let index = Int(progress) % cycleColors.count
        let nextIndex = (index + 1) % cycleColors.count
        let fraction = progress - Double(index)
        return cycleColors[index].mix(with: cycleColors[nextIndex], by: fraction)
    }
}
