import AppKit
import GhosttyKit

/// Translates macOS NSEvent keyboard events to ghostty key events.
/// Follows the same approach as Calyx and the Ghostty macOS app:
/// raw keycodes, proper modifier mapping, and text filtering.
enum KeyMapping {
    // MARK: - Modifier Translation

    static func translateModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        if flags.contains(.numericPad) { mods |= GHOSTTY_MODS_NUM.rawValue }

        let raw = flags.rawValue
        if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

        return ghostty_input_mods_e(mods)
    }

    static func modifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        let raw = mods.rawValue
        if raw & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if raw & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if raw & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if raw & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        if raw & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
        if raw & GHOSTTY_MODS_NUM.rawValue != 0 { flags.insert(.numericPad) }
        return flags
    }

    // MARK: - Key Event Translation

    static func translateKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.text = nil
        key.composing = false
        key.mods = translateModifiers(event.modifierFlags)

        let effectiveMods = translationMods ?? event.modifierFlags
        key.consumed_mods = translateModifiers(
            effectiveMods.subtracting([.control, .command])
        )

        key.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               // swiftlint:disable:next identifier_name
               let cp = chars.unicodeScalars.first
            {
                key.unshifted_codepoint = cp.value
            }
        }

        return key
    }

    // MARK: - Text Filtering

    /// Returns the text characters suitable for ghostty, or nil for special keys.
    /// Strips Private Use Area characters (arrow keys, function keys) and
    /// converts control characters to their non-control equivalents.
    static func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            // Control characters: send the non-control version
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers:
                    event.modifierFlags.subtracting(.control))
            }
            // Private Use Area (function keys, arrows, etc.): no text
            if scalar.value >= 0xF700, scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}
