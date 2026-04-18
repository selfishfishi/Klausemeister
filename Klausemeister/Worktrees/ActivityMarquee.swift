// Klausemeister/Worktrees/ActivityMarquee.swift
import SwiftUI

/// Scrolling news-headline ticker shown beneath the processing box.
/// Text slides in from the right edge, pauses at the left for `holdDuration`
/// so it's readable, then continues sliding out to the left before looping.
///
/// Driven by `phaseAnimator` (Core Animation under the hood) rather than a
/// 30 Hz `TimelineView`. The view body only re-evaluates at three
/// phase boundaries per cycle (slide-in → park → slide-out → reset) instead
/// of ~30 times per second — the between-phase motion runs on the render
/// server as a CALayer animation.
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

    private enum Phase: Hashable {
        /// Parked off-screen right, about to slide in.
        case offscreenRight
        /// Arrived at the left edge, holding for readability.
        case parkedLeft
        /// Slid past the left edge, cycle is about to reset.
        case offscreenLeft
    }

    private static let phases: [Phase] = [.offscreenRight, .parkedLeft, .offscreenLeft]

    var body: some View {
        let textWidth = estimateTextWidth(text)
        let widthDouble = Double(containerWidth)
        let slideInDuration = max(0.1, widthDouble / speed)
        let slideOutDuration = max(0.1, textWidth / speed)

        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .phaseAnimator(
                Self.phases,
                trigger: text
            ) { view, phase in
                view.offset(x: offset(for: phase, containerWidth: widthDouble, textWidth: textWidth))
            } animation: { phase in
                switch phase {
                case .offscreenRight:
                    // Wrap-around from `offscreenLeft` back to the right edge —
                    // should be instantaneous so the viewer never sees the
                    // reverse jump.
                    nil
                case .parkedLeft:
                    .linear(duration: slideInDuration)
                case .offscreenLeft:
                    // Wait at the left edge, then slide out.
                    .linear(duration: slideOutDuration).delay(holdDuration)
                }
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

    private func offset(for phase: Phase, containerWidth: Double, textWidth: Double) -> Double {
        switch phase {
        case .offscreenRight: containerWidth
        case .parkedLeft: 0
        case .offscreenLeft: -textWidth
        }
    }

    /// Quick width estimate without a full layout pass. Approximate at
    /// ~6pt per character for caption2 weight medium.
    private func estimateTextWidth(_ string: String) -> Double {
        Double(string.count) * 6.0
    }
}
