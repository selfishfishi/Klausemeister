import Foundation

struct KeyBinding: Equatable, Hashable {
    let key: Character
    let modifiers: KeyModifiers

    /// Human-readable shortcut string using macOS symbols (e.g. "⌘K", "⇧⌘D").
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(key.uppercased())
        return parts.joined()
    }
}

struct KeyModifiers: OptionSet, Equatable, Hashable {
    let rawValue: UInt8

    nonisolated static let command = KeyModifiers(rawValue: 1 << 0)
    nonisolated static let shift = KeyModifiers(rawValue: 1 << 1)
    nonisolated static let option = KeyModifiers(rawValue: 1 << 2)
    nonisolated static let control = KeyModifiers(rawValue: 1 << 3)
}
