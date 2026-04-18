import Dependencies
import Foundation

struct SurfaceManager {
    var createSurface: @Sendable @MainActor (
        _ id: String,
        _ workingDirectory: String,
        _ command: String?
    ) -> Bool
    var destroySurface: @Sendable @MainActor (_ id: String) -> Void
    var focus: @Sendable @MainActor (_ id: String) async -> Bool
    var unfocus: @Sendable @MainActor (_ id: String) -> Void
    /// Tear down all surfaces, run `appRebuild` (which frees the old
    /// `ghostty_app_t` and creates a new one), then recreate surfaces
    /// against the new app. The order is load-bearing: libghostty crashes
    /// in `ghostty_app_free` if surfaces still reference the app, and
    /// `ghostty_surface_free` is unsafe after the app is gone.
    var rebuildApp: @Sendable @MainActor (_ appRebuild: @escaping () -> Void) -> Void
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
            rebuildApp: { appRebuild in
                let snapshots = surfaceStore.snapshotAll()
                surfaceStore.destroyAll()
                appRebuild()
                guard let app = ghosttyApp.app() else { return }
                surfaceStore.restore(from: snapshots, app: app)
            }
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
        rebuildApp: unimplemented("SurfaceManager.rebuildApp", placeholder: ())
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: unimplemented(
            "SurfaceManager.createSurface",
            placeholder: false
        ),
        destroySurface: unimplemented("SurfaceManager.destroySurface"),
        focus: unimplemented("SurfaceManager.focus", placeholder: false),
        unfocus: unimplemented("SurfaceManager.unfocus"),
        rebuildApp: unimplemented("SurfaceManager.rebuildApp", placeholder: ())
    )
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
