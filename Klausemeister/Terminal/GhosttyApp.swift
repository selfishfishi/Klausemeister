import AppKit
import GhosttyKit

@MainActor
final class GhosttyApp {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    private init() {
        ghostty_init(0, nil)
        setup(theme: nil)
    }

    func rebuild(theme: AppTheme) {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
        app = nil
        config = nil
        setup(theme: theme)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func setup(theme: AppTheme?) {
        let cfg = ghostty_config_new()!
        ghostty_config_load_default_files(cfg)

        if let theme, let path = Self.writeThemeConfig(theme) {
            path.withCString { ptr in
                ghostty_config_load_file(cfg, ptr)
            }
        }

        ghostty_config_finalize(cfg)
        config = cfg

        var runtime = makeRuntimeConfig()
        app = ghostty_app_new(&runtime, cfg)
    }

    // swiftlint:disable identifier_name
    // swiftlint:disable:next cyclomatic_complexity
    private func makeRuntimeConfig() -> ghostty_runtime_config_s {
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let ref = ud
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let app = Unmanaged<GhosttyApp>.fromOpaque(ref).takeUnretainedValue()
                    app.tick()
                }
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
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { view.applyCursorShape(shape) }
                }
                return true

            case GHOSTTY_ACTION_MOUSE_VISIBILITY:
                let visibility = action.action.mouse_visibility
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { view.applyCursorVisibility(visibility) }
                }
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
