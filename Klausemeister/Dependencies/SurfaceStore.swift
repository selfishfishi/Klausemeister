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

    /// Snapshot of each surface's config used to rebuild it after a
    /// `ghostty_app_t` rebuild. Holding only value types here (no
    /// `SurfaceView`) ensures `destroyAll()` can actually deinit surfaces
    /// and call `ghostty_surface_free` while the old app is still alive.
    struct Snapshot {
        let id: String
        let workingDirectory: String
        let command: String?
    }

    /// Capture each surface's config so callers can rebuild the
    /// ghostty app and restore surfaces against the new handle.
    func snapshotAll() -> [Snapshot] {
        records.map { id, record in
            Snapshot(
                id: id,
                workingDirectory: record.workingDirectory,
                command: record.command
            )
        }
    }

    /// Recreate surfaces from a previously captured snapshot, binding each
    /// to the supplied `ghostty_app_t`.
    func restore(from snapshots: [Snapshot], app: ghostty_app_t) {
        for snapshot in snapshots {
            _ = create(
                id: snapshot.id,
                app: app,
                workingDirectory: snapshot.workingDirectory,
                command: snapshot.command
            )
        }
    }
}
