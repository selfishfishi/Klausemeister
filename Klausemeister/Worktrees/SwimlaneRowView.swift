import SwiftUI
import UniformTypeIdentifiers

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
    var onWorktreeDropped: ((_ movedWorktreeId: String) -> Void)?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !worktree.isActive || !isAnimating
        )) { timeline in
            let phase = worktree.isActive
                ? pulsePhase(date: timeline.date, period: 2.0)
                : 0.0
            let intensity = themeColors.glowIntensity

            rowContent
                .overlay {
                    RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                        .stroke(
                            themeColors.accentColor.opacity(
                                worktree.isActive ? (0.3 + 0.5 * phase) * intensity : 0
                            ),
                            lineWidth: 1.5
                        )
                }
                .shadow(
                    color: themeColors.accentColor.opacity(
                        worktree.isActive ? (0.15 + 0.25 * phase) * intensity : 0
                    ),
                    radius: worktree.isActive ? 4 + 8 * phase : 0
                )
        }
        .animation(.easeInOut(duration: 0.3), value: worktree.isActive)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            SwimlaneHeaderView(worktree: worktree)
                .draggable(WorktreeRowDragItem(worktreeId: worktree.id))
                .dropDestination(for: WorktreeRowDragItem.self) { items, _ in
                    guard let movedId = items.first?.worktreeId,
                          movedId != worktree.id,
                          let onWorktreeDropped
                    else { return false }
                    onWorktreeDropped(movedId)
                    return true
                }

            SwimlaneBarRow(
                worktree: worktree,
                teamFor: teamFor,
                onMarkComplete: onMarkComplete,
                onReturnToMeister: onReturnToMeister,
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

    private func pulsePhase(date: Date, period: Double) -> Double {
        0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
    }
}

// MARK: - Worktree Row Drag Item

private extension UTType {
    static let worktreeRowDragItem = UTType(exportedAs: "com.klausemeister.worktree-drag-item")
}

struct WorktreeRowDragItem: Codable, Transferable {
    let worktreeId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .worktreeRowDragItem)
    }
}
