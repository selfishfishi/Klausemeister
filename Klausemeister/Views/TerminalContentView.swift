import AppKit
import SwiftUI

struct TerminalContentView: NSViewRepresentable {
    let surfaceView: SurfaceView?
    let activeTabID: UUID?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true
        if let surfaceView {
            embed(surfaceView, in: container)
        }
        context.coordinator.currentTabID = activeTabID
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard activeTabID != context.coordinator.currentTabID else { return }
        context.coordinator.currentTabID = activeTabID

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
            surfaceView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    final class Coordinator {
        var currentTabID: UUID?
    }
}
