import SwiftUI

struct WorktreeTerminalTabView: View {
    let worktree: Worktree
    let surfaceView: SurfaceView?
    var onTicketTapped: ((_ issueId: String) -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        ZStack {
            if let surfaceView {
                TerminalContentView(surfaceView: surfaceView, activeID: worktree.id)
            } else {
                Color(hexString: themeColors.background)
            }

            if let processing = worktree.processing {
                ActiveTicketBanner(
                    issue: processing,
                    onTapped: onTicketTapped.map { callback in
                        { callback(processing.id) }
                    }
                )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
    }
}

private struct ActiveTicketBanner: View {
    let issue: LinearIssue
    var onTapped: (() -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Button {
            onTapped?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ticket")
                    .imageScale(.small)
                    .foregroundStyle(themeColors.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(issue.identifier)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeColors.accentColor)
                        Text(issue.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.fill.quaternary, in: Capsule())
                    }
                    Text(issue.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color(hexString: themeColors.background).opacity(0.86),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(themeColors.accentColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onTapped == nil)
        .help("\(issue.identifier) · \(issue.title)")
    }
}
