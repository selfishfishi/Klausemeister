import SwiftUI

/// Continuously-scrolling right-to-left text, stock-ticker style. Renders
/// the string twice separated by `gap` and animates the horizontal offset
/// so the first copy hands off to the second for a seamless loop. Edges
/// fade via a gradient mask so entry/exit feels soft. Paused when the
/// `\.swimlaneAnimating` environment flag is false (window backgrounded),
/// matching the pulse convention used by `MeisterStatusDot`.
struct TickerText: View {
    let text: String
    /// Horizontal scroll rate in points per second.
    var speed: CGFloat = 40
    /// Visual spacing between the two rendered copies.
    var gap: CGFloat = 32

    @Environment(\.swimlaneAnimating) private var isAnimating
    @State private var textWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            // Invisible measurer — gives us the single-copy width that drives
            // the loop period. `onGeometryChange` is main-actor-isolated so
            // it plays cleanly with Swift 6 strict concurrency.
            Text(text)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newValue in
                    textWidth = newValue
                }

            TimelineView(.animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isAnimating
            )) { timeline in
                let period = textWidth + gap
                let offset: CGFloat = period > 0
                    ? -CGFloat(
                        (timeline.date.timeIntervalSinceReferenceDate * Double(speed))
                            .truncatingRemainder(dividingBy: Double(period))
                    )
                    : 0

                HStack(spacing: gap) {
                    Text(text).fixedSize()
                    Text(text).fixedSize()
                }
                .offset(x: offset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
