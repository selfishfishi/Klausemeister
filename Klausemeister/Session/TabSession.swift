import Foundation

@MainActor
@Observable
final class TabSession: Identifiable {
    let id = UUID()
    var title: String = "Terminal"
    let surfaceView: SurfaceView

    init(surfaceView: SurfaceView) {
        self.surfaceView = surfaceView
    }
}
