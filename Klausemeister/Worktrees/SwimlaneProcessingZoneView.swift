import SwiftUI

struct SwimlaneProcessingZoneView: View {
    let issue: LinearIssue?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwimlaneZoneHeader(icon: "gearshape", title: "PROCESSING", count: issue != nil ? 1 : 0)
            if let issue {
                activeCard(issue)
            } else {
                SwimlaneEmptyPlaceholder(label: "Nothing in progress")
            }
        }
        .padding(8)
        .frame(minWidth: 160, idealWidth: 200, alignment: .topLeading)
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(themeColors.accentColor)
            .frame(width: 3)
            .padding(.vertical, 4)
    }

    private func activeCard(_ issue: LinearIssue) -> some View {
        ShimmerCard(accentColor: themeColors.accentColor, glowIntensity: themeColors.glowIntensity) {
            HStack(spacing: 0) {
                accentBar
                IssueCardView(issue: issue)
            }
        }
    }
}

private struct ShimmerCard<Content: View>: View {
    let accentColor: Color
    let glowIntensity: Double
    @ViewBuilder let content: Content

    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let period = 2.2
            let rawPhase = (time / period).truncatingRemainder(dividingBy: 1.0)
            let shimmerX = -0.4 + rawPhase * 1.8

            content
                .background {
                    ZStack {
                        accentColor.opacity(0.06)
                        shimmerGradient(position: shimmerX)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shimmerGradient(position: Double) -> some View {
        let peak = 0.22 * glowIntensity
        let edge = 0.12 * glowIntensity
        return LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, position - 0.18)),
                .init(color: accentColor.opacity(edge), location: max(0, position - 0.08)),
                .init(color: accentColor.opacity(peak), location: max(0, min(1, position))),
                .init(color: accentColor.opacity(edge), location: min(1, position + 0.08)),
                .init(color: .clear, location: min(1, position + 0.18))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
