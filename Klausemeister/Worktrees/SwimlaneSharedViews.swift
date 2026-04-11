import SwiftUI

/// Corner radius shared across the swimlane panel's glass containers —
/// rows, zones, the expanded detail pane, and drop-target overlays —
/// so the surfaces stay visually coherent if the radius is tuned.
let swimlaneGlassCornerRadius: CGFloat = 10

struct SwimlaneZoneHeader: View {
    let icon: String
    let title: String
    let count: Int
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(labelColor)
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(labelColor)
                .tracking(0.3)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(labelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(badgeBackground, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(badgeBorder, lineWidth: 0.5)
                )
        }
    }

    private var labelColor: Color {
        tint ?? .secondary
    }

    private var badgeBackground: Color {
        (tint ?? .secondary).opacity(0.15)
    }

    private var badgeBorder: Color {
        (tint ?? .secondary).opacity(0.35)
    }
}

struct SwimlaneEmptyPlaceholder: View {
    let label: String
    var tint: Color?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = 0.5 + 0.5 * sin(time * .pi * 2.0 / 3.0)
            let intensity = themeColors.glowIntensity
            let borderAlpha = (0.15 + 0.25 * wave) * intensity
            let textAlpha = 0.4 + 0.25 * wave
            let color = tint ?? .secondary

            Text(label)
                .font(.footnote)
                .foregroundStyle(color.opacity(textAlpha))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            color.opacity(borderAlpha),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                }
        }
    }
}
