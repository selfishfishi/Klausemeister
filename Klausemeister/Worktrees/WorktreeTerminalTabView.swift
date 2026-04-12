import SwiftUI

struct WorktreeTerminalTabView: View {
    let worktree: Worktree
    let surfaceView: SurfaceView?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        ZStack {
            if let surfaceView {
                TerminalContentView(surfaceView: surfaceView, activeID: worktree.id)
            } else {
                Color(hexString: themeColors.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
    }
}
