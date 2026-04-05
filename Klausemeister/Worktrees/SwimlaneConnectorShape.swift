import SwiftUI

struct SwimlaneConnectorShape: View {
    var isActive: Bool = false

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let midX = size.width / 2
            let arrowSize: CGFloat = 5

            var path = Path()
            path.move(to: CGPoint(x: midX - arrowSize, y: midY - arrowSize))
            path.addLine(to: CGPoint(x: midX + arrowSize, y: midY))
            path.addLine(to: CGPoint(x: midX - arrowSize, y: midY + arrowSize))

            let color: Color = isActive
                ? themeColors.accentColor.opacity(0.6)
                : Color.secondary.opacity(0.3)
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: 24)
    }
}
