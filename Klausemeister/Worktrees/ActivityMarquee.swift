// Klausemeister/Worktrees/ActivityMarquee.swift
import SwiftUI

/// Scrolling news-headline ticker shown beneath the processing box.
/// Text slides in from the left and travels right, then loops. When the
/// `text` value changes the scroll resets so the new message is
/// immediately visible before resuming its slide.
struct ActivityMarquee: View {
    let text: String
    var tint: Color = .secondary

    /// Pixels per second. Slow enough to read, fast enough to feel live.
    private let speed: Double = 40
    /// How long the text sits fully visible before starting to scroll.
    private let holdDuration: Double = 1.5

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let containerWidth = proxy.size.width
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                marqueeContent(elapsed: elapsed, containerWidth: containerWidth)
            }
        }
        .frame(height: 16)
        .clipped()
    }

    private func marqueeContent(elapsed: Double, containerWidth: Double) -> some View {
        let textWidth = estimateTextWidth(text)
        let totalTravel = containerWidth + textWidth
        let scrollDuration = totalTravel / speed
        let cycleDuration = holdDuration + scrollDuration
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        let offsetX = cycleElapsed < holdDuration
            ? 0.0
            : ((cycleElapsed - holdDuration) / scrollDuration) * totalTravel - textWidth

        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .offset(x: offsetX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(text)
    }

    /// Quick width estimate without a full layout pass. Approximate at
    /// ~6pt per character for caption2 weight medium.
    private func estimateTextWidth(_ string: String) -> Double {
        Double(string.count) * 6.0
    }
}
