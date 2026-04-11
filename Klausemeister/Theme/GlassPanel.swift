import SwiftUI

/// Reusable Liquid Glass container treatment: ultraThinMaterial base, tinted
/// gradient overlay, hairline gradient stroke, continuous corner radius, and
/// the twin tint + depth shadows used across the Meister redesign.
///
/// Pulled out of `KanbanColumnView` so that sheets and other panels can match
/// the kanban column look without duplicating the modifier chain.
struct GlassPanelStyle: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: tint.opacity(0.18), radius: 20, y: 8)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.08),
                                tint.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        tint.opacity(0.35),
                        tint.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
    }
}

extension View {
    func glassPanel(tint: Color, cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassPanelStyle(tint: tint, cornerRadius: cornerRadius))
    }
}
