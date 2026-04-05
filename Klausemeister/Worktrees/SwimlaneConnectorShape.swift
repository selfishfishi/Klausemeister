import SwiftUI

struct SwimlaneConnectorShape: View {
    var isActive: Bool = false

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(
            minimumInterval: isActive ? 1.0 / 60.0 : 1.0 / 20.0,
            paused: !isAnimating
        )) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = themeColors.glowIntensity
                if isActive {
                    drawActiveConnector(context: context, size: size, time: time, intensity: intensity)
                } else {
                    drawInactiveConnector(context: context, size: size, time: time)
                }
            }
        }
        .frame(width: 24)
    }

    // MARK: - Active: glowing rail + flowing dots + pulsing chevron

    private func drawActiveConnector(
        context: GraphicsContext, size: CGSize, time: Double, intensity: Double
    ) {
        let midY = size.height / 2
        let width = size.width

        // Rail line
        var rail = Path()
        rail.move(to: CGPoint(x: 0, y: midY))
        rail.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(
            rail,
            with: .color(themeColors.accentColor.opacity(0.3 * intensity)),
            lineWidth: 1
        )

        // Flowing dots
        let dotCount = 3
        let cycleLength = width + 12
        let speed: Double = 25
        for dotIndex in 0 ..< dotCount {
            let offset = CGFloat(dotIndex) * (cycleLength / CGFloat(dotCount))
            let rawPos = CGFloat(time * speed).truncatingRemainder(dividingBy: cycleLength) + offset
            let dotX = rawPos.truncatingRemainder(dividingBy: cycleLength)

            guard dotX >= -4, dotX <= width + 4 else { continue }

            // Outer bloom
            let bloom = Path(ellipseIn: CGRect(x: dotX - 5, y: midY - 5, width: 10, height: 10))
            context.fill(bloom, with: .color(themeColors.accentColor.opacity(0.12 * intensity)))

            // Inner glow
            let glow = Path(ellipseIn: CGRect(x: dotX - 3.5, y: midY - 3.5, width: 7, height: 7))
            context.fill(glow, with: .color(themeColors.accentColor.opacity(0.35 * intensity)))

            // Core dot
            let core = Path(ellipseIn: CGRect(x: dotX - 2, y: midY - 2, width: 4, height: 4))
            context.fill(core, with: .color(themeColors.accentColor.opacity(0.9 * intensity)))
        }

        // Pulsing chevron
        let chevronOpacity = (0.5 + 0.4 * sin(time * 2 * .pi / 1.5)) * intensity
        drawChevron(context: context, size: size, opacity: chevronOpacity, lineWidth: 2)

        // Chevron bloom
        let bloomOpacity = (0.2 + 0.15 * sin(time * 2 * .pi / 1.5)) * intensity
        drawChevron(context: context, size: size, opacity: bloomOpacity, lineWidth: 4)
    }

    // MARK: - Inactive: dim drifting dashes + static chevron

    private func drawInactiveConnector(context: GraphicsContext, size: CGSize, time: Double) {
        let midY = size.height / 2

        var rail = Path()
        rail.move(to: CGPoint(x: 0, y: midY))
        rail.addLine(to: CGPoint(x: size.width, y: midY))

        let phase = CGFloat(time * 4).truncatingRemainder(dividingBy: 12)
        context.stroke(
            rail,
            with: .color(Color.secondary.opacity(0.2)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 8], dashPhase: -phase)
        )

        drawChevron(context: context, size: size, opacity: 0.25, lineWidth: 1.5)
    }

    // MARK: - Chevron helper

    private func drawChevron(
        context: GraphicsContext, size: CGSize, opacity: Double, lineWidth: CGFloat
    ) {
        let midX = size.width / 2
        let midY = size.height / 2
        let arrowSize: CGFloat = 5

        var path = Path()
        path.move(to: CGPoint(x: midX - arrowSize, y: midY - arrowSize))
        path.addLine(to: CGPoint(x: midX + arrowSize, y: midY))
        path.addLine(to: CGPoint(x: midX - arrowSize, y: midY + arrowSize))

        context.stroke(
            path,
            with: .color(themeColors.accentColor.opacity(opacity)),
            lineWidth: lineWidth
        )
    }
}
