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
        if let record = records.removeValue(forKey: id) {
            record.view.teardown()
        }
    }

    func surface(for id: String) -> SurfaceView? {
        records[id]?.view
    }

    func focus(_ id: String) async -> Bool {
        guard let record = records[id] else { return false }
        let view = record.view
        // Fast path: already in a window and ready to accept first responder.
        if let window = view.window, window.makeFirstResponder(view) {
            return true
        }
        // Otherwise await `viewDidMoveToWindow`, racing a 500ms ceiling so a
        // detached surface can't hang a focus request.
        let window: NSWindow? = await withTaskGroup(of: NSWindow?.self) { group in
            group.addTask { @MainActor in await view.awaitWindow() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            for await _ in group {}
            return first
        }
        guard let window else { return false }
        return window.makeFirstResponder(view)
    }

    func unfocus(_ id: String) {
        guard let record = records[id], let surface = record.view.surface else { return }
        ghostty_surface_set_focus(surface, false)
    }

    /// Tear down every surface synchronously. MUST run before
    /// `ghostty_app_free`: libghostty's internal surface tracker holds
    /// references that become dangling once the app is freed, and
    /// dictionary removal alone doesn't trigger `SurfaceView.deinit` while
    /// SwiftUI/NSView hierarchy still retains the view wrapper.
    func destroyAll() {
        for record in records.values {
            record.view.teardown()
        }
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
