import SwiftUI

/// Glass-style kanban column with per-stage Everforest tint. The column's
/// `id` (a `MeisterState`) drives the tint applied to the header, count
/// badge, accent line, container border, and propagated to each card.
struct KanbanColumnView: View {
    let column: MeisterFeature.KanbanColumn
    let worktrees: [Worktree]
    let repositories: [Repository]
    var assignedWorktreeNames: [String: String] = [:]
    var teamsByID: [String: LinearTeam] = [:]
    let onMoveToStatus: (_ issueId: String, _ target: MeisterState) -> Void
    let onAssignToWorktree: (_ issue: LinearIssue, _ worktreeId: String) -> Void
    let onRemove: (_ issueId: String) -> Void
    let onDrop: (_ issueId: String) -> Void
    var onCardTapped: ((_ issueId: String) -> Void)?

    @Environment(\.themeColors) private var themeColors

    private var tint: Color {
        column.id.tint
    }

    private var showTeamBadges: Bool {
        !teamsByID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            accentLine
            cards
        }
        .frame(minWidth: 240, idealWidth: 260)
        .glassEffect(
            .regular.tint(tint.opacity(0.015)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let issueId = items.first else { return false }
            onDrop(issueId)
            return true
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Text(column.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .tracking(0.3)
            Spacer(minLength: 0)
            countBadge
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var countBadge: some View {
        Text("\(column.issues.count)")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var accentLine: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.7),
                        tint.opacity(0.2),
                        tint.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var cards: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 10) {
                ForEach(column.issues, id: \.id) { issue in
                    let team = showTeamBadges ? teamsByID[issue.teamId] : nil
                    KanbanIssueCardView(
                        issue: issue,
                        tint: tint,
                        worktrees: worktrees,
                        repositories: repositories,
                        worktreeName: assignedWorktreeNames[issue.id],
                        teamKey: team?.key,
                        teamTint: team.map { themeColors.teamTint(colorIndex: $0.colorIndex) },
                        onMoveToStatus: onMoveToStatus,
                        onAssignToWorktree: onAssignToWorktree,
                        onRemove: onRemove,
                        onCardTapped: onCardTapped
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }
}
