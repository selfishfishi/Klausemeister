import ComposableArchitecture
import SwiftUI

struct TerminalContainerView: View {
    let store: StoreOf<AppFeature>
    let surfaceStore: SurfaceStore

    var body: some View {
        HStack(spacing: 0) {
            if store.showSidebar {
                SidebarView(store: store)
                Divider()
            }
            TerminalContentView(
                surfaceView: store.activeTabID.flatMap { surfaceStore.surface(for: $0) },
                activeTabID: store.activeTabID
            )
        }
        .ignoresSafeArea()
        .task { store.send(.onAppear) }
    }
}
