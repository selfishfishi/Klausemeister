import SwiftUI

struct SwimlaneZoneHeader: View {
    let icon: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.fill.quaternary, in: Capsule())
        }
    }
}

struct SwimlaneEmptyPlaceholder: View {
    let label: String

    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = 0.5 + 0.5 * sin(time * .pi * 2.0 / 3.0)
            let borderAlpha = 0.1 + 0.2 * wave
            let textAlpha = 0.35 + 0.2 * wave

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(textAlpha))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(borderAlpha))
                }
        }
    }
}
