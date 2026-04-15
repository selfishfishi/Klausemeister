import SwiftUI

struct SwimlaneRowView: View {
    let worktree: Worktree
    /// Unique per-row tint resolved by the parent from the theme's swimlane
    /// palette. Used as the glass container tint so each lane reads as its
    /// own surface. The 30fps active pulse still uses `accentColor` so all
    /// "work is happening" cues read the same across rows.
    let tint: Color
    let onDelete: () -> Void
    let onRemove: () -> Void
    var teamFor: ((_ issueId: String) -> LinearTeam?)?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDropToInbox: ((_ issueId: String) -> Void)?
    var onDropToProcessing: ((_ issueId: String) -> Void)?
    var onDropToOutbox: ((_ issueId: String) -> Void)?
    var onSelectIssue: ((_ issueId: String) -> Void)?
    var onSendSlashCommand: ((_ slashCommand: String) -> Void)?
    var onMoveIssueStatus: ((_ issueId: String, _ target: MeisterState) -> Void)?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        rowContent
            .overlay {
                if worktree.isActive {
                    ActiveGlowOverlay(
                        accentColor: themeColors.accentColor,
                        glowIntensity: themeColors.glowIntensity,
                        isAnimating: isAnimating
                    )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: worktree.isActive)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            SwimlaneHeaderView(worktree: worktree)

            SwimlaneBarRow(
                worktree: worktree,
                teamFor: teamFor,
                onMarkComplete: onMarkComplete,
                onReturnToMeister: onReturnToMeister,
                onSelectIssue: onSelectIssue,
                onSendSlashCommand: onSendSlashCommand,
                onMoveIssueStatus: onMoveIssueStatus,
                onDropToInbox: onDropToInbox,
                onDropToProcessing: onDropToProcessing,
                onDropToOutbox: onDropToOutbox
            )
        }
        .padding(10)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete worktree", systemImage: "trash")
                }
                Button { onRemove() } label: {
                    Label("Remove from Klausemeister", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .glassEffect(
            .regular.tint(tint.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
        )
    }
}

/// Lightweight view that contains the 30fps TimelineView for the active
/// glow pulse. Extracted so the timeline ticks only re-evaluate this
/// overlay — not the entire `rowContent` subtree (pills, menus, stats).
private struct ActiveGlowOverlay: View {
    let accentColor: Color
    let glowIntensity: Double
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !isAnimating
        )) { timeline in
            let phase = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.0)
            RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                .stroke(
                    accentColor.opacity((0.3 + 0.5 * phase) * glowIntensity),
                    lineWidth: 1.5
                )
                .shadow(
                    color: accentColor.opacity((0.15 + 0.25 * phase) * glowIntensity),
                    radius: 4 + 8 * phase
                )
        }
    }
}
