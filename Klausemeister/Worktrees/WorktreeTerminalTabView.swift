import AppKit
import SwiftUI

struct WorktreeTerminalTabView: View {
    let worktree: Worktree
    let surfaceView: SurfaceView?

    var body: some View {
        ZStack {
            if let surfaceView {
                TerminalContentView(surfaceView: surfaceView, activeID: worktree.id)
                    .opacity(overlayMessage != nil ? 0.4 : 1.0)
            } else {
                Color(NSColor.windowBackgroundColor)
            }

            if let overlayMessage {
                VStack(spacing: 12) {
                    if worktree.meisterStatus == .spawning {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    Text(overlayMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlayMessage: String? {
        switch worktree.meisterStatus {
        case .spawning:
            "Starting Meister…"
        case .disconnected:
            "Meister disconnected"
        case .none, .running:
            // `.none` means no active spawn — either we intentionally skipped
            // it (pre-existing session) or we haven't started yet. Either way
            // do not lie about "starting"; show the bare terminal underneath.
            nil
        }
    }
}
