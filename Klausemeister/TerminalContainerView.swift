import SwiftUI

struct TerminalContainerView: View {
    let windowState: WindowState

    var body: some View {
        HStack(spacing: 0) {
            if windowState.showSidebar {
                SidebarView(windowState: windowState)
                Divider()
            }
            TerminalContentView(
                surfaceView: windowState.activeTab?.surfaceView,
                activeTabID: windowState.activeTabID
            )
        }
        .ignoresSafeArea()
    }
}
