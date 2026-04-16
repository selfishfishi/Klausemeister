import SwiftUI

/// Text with a bright band that sweeps left-to-right on a loop,
/// giving a metallic shimmer effect. Used on the sidebar worktree
/// name while the meister is actively working.
struct ShimmerText: View {
    let text: String
    let baseColor: Color
    let highlightColor: Color

    /// Seconds for one full sweep across the text.
    var period: Double = 2.0
    /// Width of the bright band as a fraction of the text (0→1).
    var bandWidth: Double = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let progress = (timeline.date.timeIntervalSinceReferenceDate / period)
                .truncatingRemainder(dividingBy: 1.0)
            // Sweep from before the leading edge to past the trailing edge
            // so the band enters and exits cleanly.
            let center = -bandWidth + progress * (1.0 + 2 * bandWidth)

            Text(text)
                .lineLimit(1)
                .foregroundStyle(
                    .linearGradient(
                        stops: [
                            .init(color: baseColor, location: max(0, center - bandWidth)),
                            .init(color: highlightColor, location: center),
                            .init(color: baseColor, location: min(1, center + bandWidth))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}
