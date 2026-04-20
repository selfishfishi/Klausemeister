import Dependencies
import Foundation
import GhosttyKit

struct SurfaceManager {
    var createSurface: @Sendable @MainActor (
        _ id: String,
        _ workingDirectory: String,
        _ command: String?
    ) -> Bool
    var destroySurface: @Sendable @MainActor (_ id: String) -> Void
    var focus: @Sendable @MainActor (_ id: String) async -> Bool
    var unfocus: @Sendable @MainActor (_ id: String) -> Void
    /// Push a new `ghostty_config_t` to every live surface. Called from
    /// `AppFeature.themeChanged` after `GhosttyApp.rebuild` has updated
    /// the app-level config — surfaces don't auto-inherit app updates.
    /// The caller retains ownership of `config` (borrowed by
    /// `ghostty_surface_update_config`).
    var applyConfigToAll: @Sendable @MainActor (_ config: ghostty_config_t) -> Void
}

extension SurfaceManager {
    static func live(surfaceStore: SurfaceStore, ghosttyApp: GhosttyAppClient) -> Self {
        SurfaceManager(
            createSurface: { id, workingDirectory, command in
                guard let app = ghosttyApp.app() else { return false }
                return surfaceStore.create(
                    id: id,
                    app: app,
                    workingDirectory: workingDirectory,
                    command: command
                )
            },
            destroySurface: { id in surfaceStore.destroy(id: id) },
            focus: { id in await surfaceStore.focus(id) },
            unfocus: { id in surfaceStore.unfocus(id) },
            applyConfigToAll: { config in surfaceStore.applyConfig(config) }
        )
    }
}

extension SurfaceManager: DependencyKey {
    /// The real instance is built via `.live(surfaceStore:ghosttyApp:)` and
    /// injected through `withDependencies` at `Store` creation. Accessing
    /// these defaults means the override never ran — fail loudly so the
    /// bug surfaces instead of silently no-oping.
    nonisolated static let liveValue = SurfaceManager(
        createSurface: unimplemented(
            "SurfaceManager.createSurface",
            placeholder: false
        ),
        destroySurface: unimplemented("SurfaceManager.destroySurface"),
        focus: unimplemented("SurfaceManager.focus", placeholder: false),
        unfocus: unimplemented("SurfaceManager.unfocus"),
        applyConfigToAll: unimplemented("SurfaceManager.applyConfigToAll")
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: unimplemented(
            "SurfaceManager.createSurface",
            placeholder: false
        ),
        destroySurface: unimplemented("SurfaceManager.destroySurface"),
        focus: unimplemented("SurfaceManager.focus", placeholder: false),
        unfocus: unimplemented("SurfaceManager.unfocus"),
        applyConfigToAll: unimplemented("SurfaceManager.applyConfigToAll")
    )
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
