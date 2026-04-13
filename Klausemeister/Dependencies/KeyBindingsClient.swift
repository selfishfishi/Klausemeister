// Klausemeister/Dependencies/KeyBindingsClient.swift
import Dependencies
import Foundation
import OSLog

struct KeyBindingsClient {
    /// Loads user overrides. A `nil` value for a command means "explicitly
    /// cleared" (the user intentionally removed the shortcut). A missing
    /// key means "use default."
    var loadOverrides: @Sendable () async throws -> [AppCommand: KeyBinding?]
    var saveOverrides: @Sendable (_ overrides: [AppCommand: KeyBinding?]) async throws -> Void
    var exportToFile: @Sendable (_ url: URL, _ bindings: [AppCommand: KeyBinding]) async throws -> Void
    var importFromFile: @Sendable (_ url: URL) async throws -> [AppCommand: KeyBinding]
    /// Captures the next key combination the user presses. Returns an
    /// AsyncStream that yields one `KeyBinding` and then finishes. The
    /// underlying NSEvent monitor consumes the event so it doesn't reach
    /// the terminal. The stream terminates on cancellation.
    var captureNextKeyBinding: @Sendable () -> AsyncStream<KeyBinding>
}

extension KeyBindingsClient: DependencyKey {
    nonisolated static let liveValue: KeyBindingsClient = {
        let log = Logger(subsystem: "com.klausemeister", category: "KeyBindingsClient")

        let configURL: URL = {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let appDir = appSupport.appendingPathComponent("Klausemeister")
            try? FileManager.default.createDirectory(
                at: appDir, withIntermediateDirectories: true
            )
            return appDir.appendingPathComponent("keybindings.json")
        }()

        let encoder: JSONEncoder = {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            return enc
        }()

        @Sendable func encodeOverrides(_ bindings: [AppCommand: KeyBinding?]) throws -> Data {
            let dict = Dictionary(
                uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }
            )
            return try encoder.encode(dict)
        }

        @Sendable func decodeOverrides(_ data: Data) throws -> [AppCommand: KeyBinding?] {
            let dict = try JSONDecoder().decode([String: KeyBinding?].self, from: data)
            var result: [AppCommand: KeyBinding?] = [:]
            for (rawValue, binding) in dict {
                guard let command = AppCommand(rawValue: rawValue) else {
                    log.info("Ignoring unrecognized command in keybindings: '\(rawValue)'")
                    continue
                }
                result[command] = binding // nil = explicitly cleared
            }
            return result
        }

        @Sendable func encodeExport(_ bindings: [AppCommand: KeyBinding]) throws -> Data {
            let dict = Dictionary(
                uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }
            )
            return try encoder.encode(dict)
        }

        @Sendable func decodeImport(_ data: Data) throws -> [AppCommand: KeyBinding] {
            let dict = try JSONDecoder().decode([String: KeyBinding].self, from: data)
            return Dictionary(uniqueKeysWithValues: dict.compactMap { rawValue, binding in
                guard let command = AppCommand(rawValue: rawValue) else {
                    log.info("Ignoring unrecognized command in keybindings: '\(rawValue)'")
                    return nil
                }
                return (command, binding)
            })
        }

        return KeyBindingsClient(
            loadOverrides: {
                guard FileManager.default.fileExists(atPath: configURL.path) else {
                    return [:]
                }
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: configURL)
                }.value
                return try decodeOverrides(data)
            },
            saveOverrides: { overrides in
                // Only persist entries that differ from defaults:
                // - binding != default → store the override
                // - binding is nil but default exists → store null (explicitly cleared)
                let nonDefaults = overrides.filter { command, binding in
                    binding != command.defaultBinding
                }
                if nonDefaults.isEmpty {
                    try? FileManager.default.removeItem(at: configURL)
                    return
                }
                let data = try encodeOverrides(nonDefaults)
                try await Task.detached(priority: .utility) {
                    try data.write(to: configURL, options: .atomic)
                }.value
            },
            exportToFile: { url, bindings in
                let data = try encodeExport(bindings)
                try data.write(to: url, options: .atomic)
            },
            importFromFile: { url in
                let data = try Data(contentsOf: url)
                return try decodeImport(data)
            },
            captureNextKeyBinding: {
                AsyncStream { continuation in
                    Task { @MainActor in
                        let monitor = NSEventMonitorStream.installKeyDownMonitor { binding in
                            continuation.yield(binding)
                            continuation.finish()
                        }
                        continuation.onTermination = { @Sendable _ in
                            Task { @MainActor in
                                NSEventMonitorStream.removeMonitor(monitor)
                            }
                        }
                    }
                }
            }
        )
    }()

    nonisolated static let testValue = KeyBindingsClient(
        loadOverrides: unimplemented("KeyBindingsClient.loadOverrides"),
        saveOverrides: unimplemented("KeyBindingsClient.saveOverrides"),
        exportToFile: unimplemented("KeyBindingsClient.exportToFile"),
        importFromFile: unimplemented("KeyBindingsClient.importFromFile"),
        captureNextKeyBinding: unimplemented(
            "KeyBindingsClient.captureNextKeyBinding",
            placeholder: AsyncStream { $0.finish() }
        )
    )
}

extension DependencyValues {
    var keyBindingsClient: KeyBindingsClient {
        get { self[KeyBindingsClient.self] }
        set { self[KeyBindingsClient.self] = newValue }
    }
}
