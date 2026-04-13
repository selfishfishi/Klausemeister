// Klausemeister/ShortcutCenter/NSEventMonitorStream.swift
import AppKit

/// Thin wrapper around NSEvent local monitoring. Used by KeyBindingsClient
/// to capture key events without exposing AppKit types to the reducer layer.
enum NSEventMonitorStream {
    /// Installs a local key-down monitor that translates NSEvents into
    /// KeyBinding values. Returns an opaque monitor object that must be
    /// removed via `removeMonitor(_:)` when done.
    @MainActor static func installKeyDownMonitor(
        handler: @escaping (KeyBinding) -> Void
    ) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let binding = KeyBinding(nsEvent: event) {
                handler(binding)
                return nil // consume — don't forward to terminal
            }
            return event // pass through modifier-only or unrecognized keys
        } as Any
    }

    @MainActor static func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}
