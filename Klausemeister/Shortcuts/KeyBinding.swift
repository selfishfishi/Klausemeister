import Foundation

struct KeyBinding: Equatable, Hashable, Codable {
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

    // MARK: - Codable (Character is not natively Codable)

    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }

    nonisolated init(key: Character, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyString = try container.decode(String.self, forKey: .key)
        guard let char = keyString.first, keyString.count == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .key, in: container,
                debugDescription: "Expected single character"
            )
        }
        key = char
        modifiers = try container.decode(KeyModifiers.self, forKey: .modifiers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(key), forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
    }
}

struct KeyModifiers: OptionSet, Equatable, Hashable, Codable {
    let rawValue: UInt8

    nonisolated static let command = KeyModifiers(rawValue: 1 << 0)
    nonisolated static let shift = KeyModifiers(rawValue: 1 << 1)
    nonisolated static let option = KeyModifiers(rawValue: 1 << 2)
    nonisolated static let control = KeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
