import AppKit
import GhosttyKit

/// Manages the ghostty application lifecycle. One instance per app.
@MainActor
final class GhosttyApp {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    private init() {
        ghostty_init(0, nil)

        let cfg = ghostty_config_new()!
        ghostty_config_load_default_files(cfg)
        ghostty_config_finalize(cfg)
        self.config = cfg

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let ref = ud
            DispatchQueue.main.async {
                let app = Unmanaged<GhosttyApp>.fromOpaque(ref).takeUnretainedValue()
                app.tick()
            }
        }
        runtime.action_cb = { _, _, _ in false }

        // read_clipboard_cb: (userdata, clipboard_type, state) -> bool
        // Read from pasteboard and complete the request via state pointer.
        runtime.read_clipboard_cb = { ud, clipboard, state in
            let content = NSPasteboard.general.string(forType: .string) ?? ""
            content.withCString { ptr in
                // state is an opaque completion token; pass it back with the content
                ghostty_surface_complete_clipboard_request(state, ptr, nil, false)
            }
            return true
        }

        // confirm_read_clipboard_cb: (userdata, content, state, request_type)
        // Auto-confirm clipboard reads.
        runtime.confirm_read_clipboard_cb = { ud, content, state, request in
            ghostty_surface_complete_clipboard_request(state, content, nil, true)
        }

        // write_clipboard_cb: (userdata, clipboard_type, contents, count, confirm)
        runtime.write_clipboard_cb = { ud, clipboard, contents, contentsLen, confirm in
            guard contentsLen > 0, let first = contents else { return }
            if let data = first.pointee.data {
                let s = String(cString: data)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }

        runtime.close_surface_cb = { ud, processAlive in }

        self.app = ghostty_app_new(&runtime, cfg)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }
}
