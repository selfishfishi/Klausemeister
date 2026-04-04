import AppKit
import SwiftUI

struct TerminalContainerView: View {
    var body: some View {
        TerminalRepresentable()
            .ignoresSafeArea()
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView(frame: .zero)
        guard let app = GhosttyApp.shared.app else { return view }
        view.initializeSurface(app: app, workingDirectory: NSHomeDirectory())
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {}
}
