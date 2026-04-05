import AppKit
import GhosttyKit

@Observable
final class SurfaceStore {
    private(set) var surfaces: [UUID: SurfaceView] = [:]

    func create(id: UUID, app: ghostty_app_t) -> Bool {
        let view = SurfaceView(frame: .zero)
        view.initializeSurface(app: app, workingDirectory: NSHomeDirectory())
        guard view.surface != nil else { return false }
        surfaces[id] = view
        return true
    }

    func destroy(id: UUID) {
        surfaces.removeValue(forKey: id)
    }

    func surface(for id: UUID) -> SurfaceView? {
        surfaces[id]
    }

    func focus(_ id: UUID) async -> Bool {
        guard let view = surfaces[id] else { return false }
        for _ in 0..<50 {
            if let window = view.window, window.makeFirstResponder(view) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func unfocus(_ id: UUID) {
        guard let view = surfaces[id],
              let surface = view.surface else { return }
        ghostty_surface_set_focus(surface, false)
    }
}
