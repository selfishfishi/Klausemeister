// Klausemeister/Worktrees/ActivityMarquee.swift
import SwiftUI

/// Scrolling news-headline ticker shown beneath the processing box.
/// Text slides in from the right edge, pauses at the left for `holdDuration`
/// so it's readable, then continues sliding out to the left before looping.
/// Classical news-ticker direction — the first character appears first,
/// matching left-to-right reading.
struct ActivityMarquee: View {
    let text: String
    var tint: Color = .secondary

    /// Pixels per second. Slow enough to read, fast enough to feel live.
    private let speed: Double = 40
    /// How long the text sits fully visible before starting to scroll.
    private let holdDuration: Double = 1.5

    /// Width measured by a background `GeometryReader`. Using a background
    /// reader instead of a root `GeometryReader` keeps this view's layout
    /// conventional (intrinsic-height, flex-width) — a root reader reports
    /// 0 width when the parent has multiple flex-width children with no
    /// intrinsic-width siblings to anchor the stack, which is the exact
    /// layout inside `SwimlaneBarRow`.
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        // Pause when there's nothing to scroll or we haven't measured the
        // container yet. Otherwise every marquee in the list keeps ticking
        // at 30fps even when its row is idle, which compounds quickly.
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: text.isEmpty || containerWidth == 0
        )) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            marqueeContent(elapsed: elapsed, containerWidth: Double(containerWidth))
        }
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
            }
        }
        .clipped()
    }

    private func marqueeContent(elapsed: Double, containerWidth: Double) -> some View {
        let textWidth = estimateTextWidth(text)
        let slideInDuration = max(0.1, containerWidth / speed)
        let slideOutDuration = max(0.1, textWidth / speed)
        let cycleDuration = slideInDuration + holdDuration + slideOutDuration
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        let offsetX: Double
        if cycleElapsed < slideInDuration {
            // Phase 1 — slide in from the right edge to the left.
            let progress = cycleElapsed / slideInDuration
            offsetX = containerWidth * (1 - progress)
        } else if cycleElapsed < slideInDuration + holdDuration {
            // Phase 2 — hold at the left edge so the message can be read.
            offsetX = 0
        } else {
            // Phase 3 — continue scrolling left, exiting off the left edge.
            let progress = (cycleElapsed - slideInDuration - holdDuration) / slideOutDuration
            offsetX = -textWidth * progress
        }

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
