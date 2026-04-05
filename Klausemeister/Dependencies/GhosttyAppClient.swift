import Dependencies
import GhosttyKit

struct GhosttyAppClient: Sendable {
    var app: @Sendable @MainActor () -> ghostty_app_t?
    var tick: @Sendable @MainActor () -> Void
}

extension GhosttyAppClient: DependencyKey {
    nonisolated static let liveValue = GhosttyAppClient(
        app: { GhosttyApp.shared.app },
        tick: { GhosttyApp.shared.tick() }
    )
    nonisolated static let testValue = GhosttyAppClient(
        app: { nil },
        tick: { }
    )
}

extension DependencyValues {
    var ghosttyApp: GhosttyAppClient {
        get { self[GhosttyAppClient.self] }
        set { self[GhosttyAppClient.self] = newValue }
    }
}
