import Dependencies
import Foundation

struct SurfaceManager: Sendable {
    var createSurface: @Sendable @MainActor (UUID) -> Bool
    var destroySurface: @Sendable @MainActor (UUID) -> Void
    var focus: @Sendable @MainActor (UUID) async -> Bool
    var unfocus: @Sendable @MainActor (UUID) -> Void
    var recreateAllSurfaces: @Sendable @MainActor ([UUID]) -> Void
}

extension SurfaceManager {
    static func live(surfaceStore: SurfaceStore, ghosttyApp: GhosttyAppClient) -> Self {
        SurfaceManager(
            createSurface: { id in
                guard let app = ghosttyApp.app() else { return false }
                return surfaceStore.create(id: id, app: app)
            },
            destroySurface: { id in
                surfaceStore.destroy(id: id)
            },
            focus: { id in
                await surfaceStore.focus(id)
            },
            unfocus: { id in
                surfaceStore.unfocus(id)
            },
            recreateAllSurfaces: { ids in
                surfaceStore.destroyAll()
                guard let app = ghosttyApp.app() else { return }
                surfaceStore.recreateAll(ids: ids, app: app)
            }
        )
    }
}

extension SurfaceManager: DependencyKey {
    nonisolated static let liveValue = SurfaceManager(
        createSurface: { _ in false },
        destroySurface: { _ in },
        focus: { _ in false },
        unfocus: { _ in },
        recreateAllSurfaces: { _ in }
    )
    nonisolated static let testValue = SurfaceManager(
        createSurface: { _ in true },
        destroySurface: { _ in },
        focus: { _ in true },
        unfocus: { _ in },
        recreateAllSurfaces: { _ in }
    )
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
