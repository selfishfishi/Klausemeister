import AppKit
import GhosttyKit

@MainActor
@Observable
final class SurfaceStore {
    struct Record {
        let view: SurfaceView
        let workingDirectory: String
        let command: String?
    }

    private(set) var records: [String: Record] = [:]

    func create(
        id: String,
        app: ghostty_app_t,
        workingDirectory: String,
        command: String?
    ) -> Bool {
        if let existing = records[id], existing.view.surface != nil {
            return true
        }
        let view = SurfaceView(frame: .zero)
        view.initializeSurface(
            app: app,
            workingDirectory: workingDirectory,
            command: command
        )
        guard view.surface != nil else { return false }
        records[id] = Record(
            view: view,
            workingDirectory: workingDirectory,
            command: command
        )
        return true
    }

    func destroy(id: String) {
        records.removeValue(forKey: id)
    }

    func surface(for id: String) -> SurfaceView? {
        records[id]?.view
    }

    func focus(_ id: String) async -> Bool {
        guard let record = records[id] else { return false }
        for _ in 0 ..< 50 {
            if let window = record.view.window, window.makeFirstResponder(record.view) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func unfocus(_ id: String) {
        guard let record = records[id], let surface = record.view.surface else { return }
        ghostty_surface_set_focus(surface, false)
    }

    func destroyAll() {
        records.removeAll()
    }

    /// Recreate all surfaces in place using their stored config. Used after
    /// theme rebuilds, which invalidate the underlying ghostty_app_t and
    /// require fresh surfaces bound to the new app handle.
    func recreateAll(app: ghostty_app_t) {
        let snapshots = records
        records.removeAll()
        for (id, record) in snapshots {
            _ = create(
                id: id,
                app: app,
                workingDirectory: record.workingDirectory,
                command: record.command
            )
        }
    }
}
