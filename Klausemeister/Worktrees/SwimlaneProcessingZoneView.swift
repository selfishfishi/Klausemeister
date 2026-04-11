import SwiftUI

struct SwimlaneProcessingZoneView: View {
    let issue: LinearIssue?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDrop: ((_ issueId: String) -> Void)?

    private let stageTint: Color = MeisterState.inProgress.tint

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwimlaneZoneHeader(
                icon: "gearshape",
                title: "PROCESSING",
                count: issue != nil ? 1 : 0,
                tint: stageTint
            )
            if let issue {
                activeCard(issue)
            } else {
                SwimlaneEmptyPlaceholder(label: "Nothing in progress", tint: stageTint)
            }
        }
        .padding(10)
        .frame(minWidth: 160, idealWidth: 200, alignment: .topLeading)
        .glassPanel(tint: stageTint, cornerRadius: swimlaneGlassCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                .stroke(stageTint.opacity(isTargeted ? 0.7 : 0), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard issue == nil, let issueId = items.first, let onDrop else { return false }
            onDrop(issueId)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted && issue == nil
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(stageTint)
            .frame(width: 3)
            .padding(.vertical, 4)
    }

    private func activeCard(_ issue: LinearIssue) -> some View {
        ShimmerCard(accentColor: stageTint) {
            HStack(spacing: 0) {
                accentBar
                IssueCardView(issue: issue)
                    .draggable(issue.id)
            }
        }
        .contextMenu {
            if let onMarkComplete {
                Button("Mark as Done") {
                    onMarkComplete()
                }
            }
            if let onReturn = onReturnToMeister {
                Button("Return to Meister") {
                    onReturn(issue.id)
                }
            }
        }
    }
}

private struct ShimmerCard<Content: View>: View {
    let accentColor: Color
    @ViewBuilder let content: Content

    @Environment(\.themeColors) private var themeColors
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
        let peak = 0.22 * themeColors.glowIntensity
        let edge = 0.12 * themeColors.glowIntensity
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
