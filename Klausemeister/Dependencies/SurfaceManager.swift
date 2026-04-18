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
    /// Capture each live surface's config so the reducer can rebuild the
    /// `ghostty_app_t` and then restore them against the new handle.
    var captureSurfaces: @Sendable @MainActor () -> [SurfaceStore.Snapshot]
    /// Tear down every live surface. Must be called BEFORE
    /// `ghostty_app_free` — libghostty crashes in the free path when
    /// surfaces still reference the app.
    var destroyAllSurfaces: @Sendable @MainActor () -> Void
    /// Recreate surfaces from a snapshot, binding each to the current
    /// `ghostty_app_t`. Must be called AFTER the new app exists.
    var restoreSurfaces: @Sendable @MainActor (_ snapshots: [SurfaceStore.Snapshot]) -> Void
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
            captureSurfaces: { surfaceStore.snapshotAll() },
            destroyAllSurfaces: { surfaceStore.destroyAll() },
            restoreSurfaces: { snapshots in
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
        captureSurfaces: unimplemented(
            "SurfaceManager.captureSurfaces",
            placeholder: []
        ),
        destroyAllSurfaces: unimplemented("SurfaceManager.destroyAllSurfaces"),
        restoreSurfaces: unimplemented("SurfaceManager.restoreSurfaces")
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: unimplemented(
            "SurfaceManager.createSurface",
            placeholder: false
        ),
        destroySurface: unimplemented("SurfaceManager.destroySurface"),
        focus: unimplemented("SurfaceManager.focus", placeholder: false),
        unfocus: unimplemented("SurfaceManager.unfocus"),
        captureSurfaces: unimplemented(
            "SurfaceManager.captureSurfaces",
            placeholder: []
        ),
        destroyAllSurfaces: unimplemented("SurfaceManager.destroyAllSurfaces"),
        restoreSurfaces: unimplemented("SurfaceManager.restoreSurfaces")
    )
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
