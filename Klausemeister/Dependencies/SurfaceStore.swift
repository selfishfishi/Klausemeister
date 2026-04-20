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

    /// Push a new `ghostty_config_t` to every live surface. Used by
    /// `AppFeature.themeChanged` after `GhosttyApp.rebuild` has hot-reloaded
    /// the app-level config: surfaces don't auto-inherit app updates, so
    /// each one needs its own `ghostty_surface_update_config` call to
    /// repaint with the new theme.
    ///
    /// The caller retains ownership of `config` — `ghostty_surface_update_config`
    /// borrows it (matches the upstream `Ghostty.App.swift` convention).
    func applyConfig(_ config: ghostty_config_t) {
        for record in records.values {
            guard let surface = record.view.surface else { continue }
            ghostty_surface_update_config(surface, config)
        }
    }
}
