import AppKit
import SwiftUI

struct WorktreeTerminalTabView: View {
    let worktree: Worktree
    let surfaceView: SurfaceView?

    var body: some View {
        ZStack {
            if let surfaceView {
                TerminalContentView(surfaceView: surfaceView, activeID: worktree.id)
            } else {
                Color(NSColor.windowBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
