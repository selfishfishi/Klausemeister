import Foundation

struct KeyBinding: Equatable, Hashable, Sendable {
    let key: Character
    let modifiers: KeyModifiers
}

struct KeyModifiers: OptionSet, Equatable, Hashable, Sendable {
    let rawValue: UInt8

    nonisolated static let command = KeyModifiers(rawValue: 1 << 0)
    nonisolated static let shift   = KeyModifiers(rawValue: 1 << 1)
    nonisolated static let option  = KeyModifiers(rawValue: 1 << 2)
    nonisolated static let control = KeyModifiers(rawValue: 1 << 3)
}
