import Dependencies
import GhosttyKit

struct GhosttyAppClient {
    var app: @Sendable @MainActor () -> ghostty_app_t?
    var config: @Sendable @MainActor () -> ghostty_config_t?
    var tick: @Sendable @MainActor () -> Void
    var rebuild: @Sendable @MainActor (AppTheme) -> Void
}

extension GhosttyAppClient: DependencyKey {
    nonisolated static let liveValue = GhosttyAppClient(
        app: { GhosttyApp.shared.app },
        config: { GhosttyApp.shared.config },
        tick: { GhosttyApp.shared.tick() },
        rebuild: { theme in GhosttyApp.shared.rebuild(theme: theme) }
    )
    nonisolated static let testValue = GhosttyAppClient(
        app: unimplemented("GhosttyAppClient.app", placeholder: nil),
        config: unimplemented("GhosttyAppClient.config", placeholder: nil),
        tick: unimplemented("GhosttyAppClient.tick"),
        rebuild: unimplemented("GhosttyAppClient.rebuild")
    )
}

extension DependencyValues {
    var ghosttyApp: GhosttyAppClient {
        get { self[GhosttyAppClient.self] }
        set { self[GhosttyAppClient.self] = newValue }
    }
}
