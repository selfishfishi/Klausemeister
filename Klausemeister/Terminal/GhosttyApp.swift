import AppKit
import GhosttyKit
import os

@MainActor
final class GhosttyApp {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    /// Coalescing flag for `wakeup_cb`. libghostty fires the callback at
    /// display-refresh rate (60-120 Hz); without coalescing every invocation
    /// enqueues a separate `DispatchQueue.main.async` block and they pile up.
    /// The lock-protected boolean ensures at most one `tick()` is pending on
    /// the main queue at any time — subsequent wakeups while a tick is already
    /// queued are no-ops.
    nonisolated let needsTick = OSAllocatedUnfairLock(initialState: false)

    private init() {
        ghostty_init(0, nil)
        setup(theme: nil)
    }

    /// Apply a new theme without freeing the underlying `ghostty_app_t`.
    ///
    /// Hot-reloads the C-level config via `ghostty_app_update_config`. The
    /// previous code path freed and recreated `ghostty_app_t` on every theme
    /// change, leaving a use-after-free window: a `wakeup_cb` queued by the
    /// old `ghostty_app_t` could fire after `ghostty_app_free` but before the
    /// new app existed (KLA-173). Since the runtime config (callbacks,
    /// userdata) is bound at `ghostty_app_new` time and survives
    /// `update_config`, we never need to free the app for a theme swap.
    ///
    /// First-run path (called from `init` before `app` exists) falls through
    /// to `setup(theme:)` which still uses `ghostty_app_new`.
    ///
    /// Surface-level config does NOT auto-propagate from app updates — the
    /// caller (`AppFeature.themeChanged`) is responsible for pushing the
    /// new config to live surfaces via `SurfaceManager.applyConfigToAll`.
    func rebuild(theme: AppTheme) {
        guard let app else {
            // First run — no live ghostty_app_t yet, build from scratch.
            setup(theme: theme)
            return
        }
        let newCfg = Self.buildConfig(theme: theme)
        ghostty_app_update_config(app, newCfg)
        if let oldConfig = config { ghostty_config_free(oldConfig) }
        config = newCfg
        needsTick.withLock { $0 = false }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func setup(theme: AppTheme?) {
        let cfg = Self.buildConfig(theme: theme)
        config = cfg

        var runtime = makeRuntimeConfig()
        app = ghostty_app_new(&runtime, cfg)
    }

    /// Build a finalized `ghostty_config_t` for the given theme. Caller owns
    /// the returned handle and must eventually `ghostty_config_free` it (or
    /// pass it to `ghostty_app_update_config` and free the *previous* one).
    private static func buildConfig(theme: AppTheme?) -> ghostty_config_t {
        let cfg = ghostty_config_new()!
        ghostty_config_load_default_files(cfg)

        if let theme, let path = writeThemeConfig(theme) {
            path.withCString { ptr in
                ghostty_config_load_file(cfg, ptr)
            }
        }

        ghostty_config_finalize(cfg)
        return cfg
    }

    // swiftlint:disable identifier_name
    // swiftlint:disable:next cyclomatic_complexity
    private func makeRuntimeConfig() -> ghostty_runtime_config_s {
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            let shouldEnqueue = app.needsTick.withLock { needsTick in
                if needsTick { return false }
                needsTick = true
                return true
            }
            guard shouldEnqueue else { return }
            DispatchQueue.main.async {
                defer { app.needsTick.withLock { $0 = false } }
                app.tick()
            }
        }
        runtime.action_cb = { _, target, action in
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
            let surfaceHandle = target.target.surface
            guard let ud = ghostty_surface_userdata(surfaceHandle) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()

            switch action.tag {
            case GHOSTTY_ACTION_MOUSE_SHAPE:
                let shape = action.action.mouse_shape
                DispatchQueue.main.async { view.applyCursorShape(shape) }
                return true

            case GHOSTTY_ACTION_MOUSE_VISIBILITY:
                let visibility = action.action.mouse_visibility
                DispatchQueue.main.async { view.applyCursorVisibility(visibility) }
                return true

            default:
                return false
            }
        }

        runtime.read_clipboard_cb = { ud, _, state in
            guard let ud else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            guard let surface = view.surface else { return false }
            let content = NSPasteboard.general.string(forType: .string) ?? ""
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }

        runtime.confirm_read_clipboard_cb = { ud, content, state, _ in
            guard let ud else { return }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            guard let surface = view.surface else { return }
            ghostty_surface_complete_clipboard_request(surface, content, state, true)
        }

        runtime.write_clipboard_cb = { _, _, contents, contentsLen, _ in
            guard contentsLen > 0, let first = contents else { return }
            if let data = first.pointee.data {
                let s = String(cString: data)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }

        runtime.close_surface_cb = { _, _ in }

        return runtime
    }

    // swiftlint:enable identifier_name

    private static func writeThemeConfig(_ theme: AppTheme) -> String? {
        let colors = theme.colors
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Klausemeister", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let configURL = appSupport.appendingPathComponent("theme.conf")

        var lines: [String] = []
        lines.append("background = \(colors.background.dropFirst())")
        lines.append("foreground = \(colors.foreground.dropFirst())")
        lines.append("cursor-color = \(colors.cursorColor.dropFirst())")
        lines.append("selection-background = \(colors.selectionBg.dropFirst())")
        lines.append("selection-foreground = \(colors.selectionFg.dropFirst())")
        // swiftlint:disable:next identifier_name
        for (i, hex) in colors.palette.enumerated() {
            lines.append("palette = \(i)=\(hex.dropFirst())")
        }

        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return configURL.path
        } catch {
            return nil
        }
    }
}
