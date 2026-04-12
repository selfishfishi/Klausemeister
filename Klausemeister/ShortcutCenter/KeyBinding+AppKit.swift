// Klausemeister/ShortcutCenter/KeyBinding+AppKit.swift
import AppKit

extension KeyBinding {
    /// Failable init that translates an NSEvent into a KeyBinding.
    /// Returns nil for modifier-only key presses or events without characters.
    init?(nsEvent: NSEvent) {
        guard let chars = nsEvent.charactersIgnoringModifiers,
              let char = chars.first
        else {
            return nil
        }

        // Ignore bare modifier keys (Shift, Cmd, etc. pressed alone)
        let bareModifiers: Set<UInt16> = [56, 54, 55, 59, 58, 61, 62, 60]
        if bareModifiers.contains(nsEvent.keyCode) { return nil }

        var mods = KeyModifiers([])
        let flags = nsEvent.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }

        // Require at least one modifier for a valid shortcut
        guard !mods.isEmpty else { return nil }

        self.init(key: char, modifiers: mods)
    }
}
