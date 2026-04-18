import SwiftUI

/// Glass-style issue card.
///
/// `tint` is optional: callers inside the kanban (where the column's tint
/// should dominate even during an optimistic drag) pass it explicitly;
/// callers outside the kanban (worktree swimlanes, etc.) leave it `nil`
/// and the card derives its tint from `issue.meisterState`, falling back
/// to the theme accent if the mapping returns nil.
struct IssueCardView: View {
    let issue: LinearIssue
    var tint: Color?
    var worktreeName: String?
    var teamKey: String?
    var teamTint: Color?

    @Environment(\.themeColors) private var themeColors

    private var resolvedTint: Color {
        tint ?? issue.meisterState?.tint ?? themeColors.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let teamKey, let teamTint {
                    teamBadge(key: teamKey, color: teamTint)
                }
                Text(issue.identifier)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(resolvedTint)
                if issue.isOrphaned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(themeColors.warningColor)
                        .help("This issue no longer has the klause label in Linear")
                }
                Spacer(minLength: 0)
            }

            Text(issue.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if issue.projectName != nil || worktreeName != nil {
                HStack(spacing: 6) {
                    if let projectName = issue.projectName {
                        chip(text: projectName, icon: nil)
                    }
                    if let worktreeName {
                        chip(text: worktreeName, icon: "arrow.triangle.branch")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .opacity(issue.isOrphaned ? 0.55 : 1.0)
    }

    // MARK: - Pieces

    private func teamBadge(key: String, color: Color) -> some View {
        Text(key)
            .font(.system(.caption2, design: .monospaced).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(resolvedTint.opacity(0.04))
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(resolvedTint.opacity(0.4), lineWidth: 0.5)
    }

    private func chip(text: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.fill.tertiary, in: Capsule())
    }
}

// MARK: - Kanban variant (drag + context menu)

struct KanbanIssueCardView: View {
    let issue: LinearIssue
    let tint: Color
    let worktrees: [Worktree]
    let repositories: [Repository]
    var worktreeName: String?
    var teamKey: String?
    var teamTint: Color?
    let onMoveToStatus: (_ issueId: String, _ target: MeisterState) -> Void
    let onAssignToWorktree: (_ issue: LinearIssue, _ worktreeId: String) -> Void
    let onRemove: (_ issueId: String) -> Void
    var onCardTapped: ((_ issueId: String) -> Void)?

    @Environment(\.keyBindings) private var bindings

    /// Destinations for the "Move to..." menu — every canonical stage except
    /// the one the issue is already in.
    private var movableStates: [MeisterState] {
        let current = issue.meisterState
        return MeisterState.allCases.filter { $0 != current }
    }

    /// Worktrees grouped by their `repoId`. Built once per `body` pass so
    /// the context-menu builder doesn't run `.filter` over `worktrees`
    /// three times (twice per repo + once for the ungrouped tail) on
    /// every cell re-render.
    private var worktreesByRepoId: [String?: [Worktree]] {
        Dictionary(grouping: worktrees, by: \.repoId)
    }

    /// Repositories that actually have at least one worktree — the other
    /// repos would render an empty `Section`. Derived from `worktreesByRepoId`
    /// so we avoid the `repositories.filter { repo in worktrees.contains {...} }`
    /// O(N×M) pattern.
    private var reposWithWorktrees: [Repository] {
        let byRepo = worktreesByRepoId
        return repositories.filter { byRepo[$0.id]?.isEmpty == false }
    }

    var body: some View {
        Button {
            onCardTapped?(issue.id)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .draggable(issue.id)
        .contextMenu {
            Menu("Move to...") {
                ForEach(movableStates) { state in
                    Button {
                        onMoveToStatus(issue.id, state)
                    } label: {
                        Label(state.displayName, systemImage: "arrow.right.circle")
                    }
                }
            }
            if !worktrees.isEmpty {
                let byRepo = worktreesByRepoId
                let grouped = reposWithWorktrees
                Menu("Move to Worktree") {
                    ForEach(grouped) { repo in
                        Section(repo.name) {
                            ForEach(byRepo[repo.id] ?? []) { worktree in
                                Button(worktree.name) { onAssignToWorktree(issue, worktree.id) }
                            }
                        }
                    }
                    let ungrouped = byRepo[nil] ?? []
                    if !ungrouped.isEmpty {
                        if !grouped.isEmpty { Divider() }
                        ForEach(ungrouped) { worktree in
                            Button(worktree.name) { onAssignToWorktree(issue, worktree.id) }
                        }
                    }
                }
            }
            Divider()
            Button("Remove from board", role: .destructive) {
                onRemove(issue.id)
            }
            .keyboardShortcut(for: .removeIssue, in: bindings)
        }
    }

    private var cardContent: some View {
        IssueCardView(
            issue: issue,
            tint: tint,
            worktreeName: worktreeName,
            teamKey: teamKey,
            teamTint: teamTint
        )
    }
}
