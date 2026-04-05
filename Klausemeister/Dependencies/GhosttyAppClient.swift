import Dependencies
import GhosttyKit

struct GhosttyAppClient: Sendable {
    var app: @Sendable @MainActor () -> ghostty_app_t?
    var tick: @Sendable @MainActor () -> Void
    var rebuild: @Sendable @MainActor (AppTheme) -> Void
}

extension GhosttyAppClient: DependencyKey {
    nonisolated static let liveValue = GhosttyAppClient(
        app: { GhosttyApp.shared.app },
        tick: { GhosttyApp.shared.tick() },
        rebuild: { theme in GhosttyApp.shared.rebuild(theme: theme) }
    )
    nonisolated static let testValue = GhosttyAppClient(
        app: { nil },
        tick: { },
        rebuild: { _ in }
    )
}

extension DependencyValues {
    var ghosttyApp: GhosttyAppClient {
        get { self[GhosttyAppClient.self] }
        set { self[GhosttyAppClient.self] = newValue }
    }
}
