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
            let stops = gradientStops(center: center, elapsed: t)

            Text(text)
                .lineLimit(1)
                .foregroundStyle(
                    .linearGradient(
                        stops: stops,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    /// The band spans [center - bandWidth, center + bandWidth]. Inside the
    /// band we lay out every palette color as a multi-stop gradient and
    /// rotate them over time, so each sweep reveals the full theme rather
    /// than a single highlight color.
    private func gradientStops(center: Double, elapsed: Double) -> [Gradient.Stop] {
        guard !cycleColors.isEmpty else {
            return [
                .init(color: baseColor, location: 0),
                .init(color: baseColor, location: 1)
            ]
        }

        let bandStart = center - bandWidth
        let bandEnd = center + bandWidth
        let rotated = rotatedColors(at: elapsed)

        var stops: [Gradient.Stop] = [
            .init(color: baseColor, location: clamp(bandStart))
        ]

        if rotated.count == 1 {
            stops.append(.init(color: rotated[0], location: clamp(center)))
        } else {
            let spacing = (bandEnd - bandStart) / Double(rotated.count - 1)
            for (index, color) in rotated.enumerated() {
                let location = bandStart + Double(index) * spacing
                stops.append(.init(color: color, location: clamp(location)))
            }
        }

        stops.append(.init(color: baseColor, location: clamp(bandEnd)))
        return stops
    }

    private func rotatedColors(at elapsed: Double) -> [Color] {
        let count = cycleColors.count
        guard count > 1 else { return cycleColors }
        let raw = (elapsed / colorCyclePeriod).truncatingRemainder(dividingBy: 1)
        let progress = (raw < 0 ? raw + 1 : raw) * Double(count)
        let shift = Int(progress) % count
        let fraction = progress - Double(Int(progress))
        return (0 ..< count).map { index in
            let base = (index + shift) % count
            let next = (base + 1) % count
            return cycleColors[base].mix(with: cycleColors[next], by: fraction)
        }
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
