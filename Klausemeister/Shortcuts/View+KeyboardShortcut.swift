import SwiftUI

extension KeyBinding {
    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift)   { result.insert(.shift) }
        if modifiers.contains(.option)  { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

extension View {
    @ViewBuilder
    func keyboardShortcut(
        for command: AppCommand,
        in bindings: [AppCommand: KeyBinding]
    ) -> some View {
        if let binding = bindings[command] {
            self.keyboardShortcut(binding.keyEquivalent, modifiers: binding.eventModifiers)
        } else {
            self
        }
    }
}
