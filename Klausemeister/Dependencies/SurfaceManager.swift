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
    /// Rebuild every live surface against the current `ghostty_app_t`.
    /// Called after a theme change, which invalidates prior app handles.
    /// Reads stored per-surface config from the `SurfaceStore` — callers do
    /// not pass IDs.
    var recreateAllSurfaces: @Sendable @MainActor () -> Void
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
            recreateAllSurfaces: {
                guard let app = ghosttyApp.app() else { return }
                surfaceStore.recreateAll(app: app)
            }
        )
    }
}

extension SurfaceManager: DependencyKey {
    nonisolated static let liveValue = SurfaceManager(
        createSurface: { _, _, _ in false },
        destroySurface: { _ in },
        focus: { _ in false },
        unfocus: { _ in },
        recreateAllSurfaces: {}
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: { _, _, _ in true },
        destroySurface: { _ in },
        focus: { _ in true },
        unfocus: { _ in },
        recreateAllSurfaces: {}
    )
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
