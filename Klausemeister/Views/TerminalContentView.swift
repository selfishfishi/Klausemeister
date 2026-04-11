import AppKit
import SwiftUI

struct TerminalContentView: NSViewRepresentable {
    let surfaceView: SurfaceView?
    let activeID: String?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true
        if let surfaceView {
            embed(surfaceView, in: container)
        }
        context.coordinator.currentID = activeID
        context.coordinator.currentSurface = surfaceView
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard activeID != context.coordinator.currentID
            || surfaceView !== context.coordinator.currentSurface else { return }
        context.coordinator.currentID = activeID
        context.coordinator.currentSurface = surfaceView

        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        guard let surfaceView else { return }
        embed(surfaceView, in: container)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func embed(_ surfaceView: SurfaceView, in container: NSView) {
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: container.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    final class Coordinator {
        var currentID: String?
        weak var currentSurface: SurfaceView?
    }
}
