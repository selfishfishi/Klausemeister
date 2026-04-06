import SwiftUI

struct IssueCardView: View {
    let issue: LinearIssue
    var worktreeName: String?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(issue.identifier)
                    .font(.caption)
                    .foregroundStyle(themeColors.accentColor.opacity(0.8))
                if issue.isOrphaned {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(themeColors.warningColor)
                        .help("This issue no longer has the klause label in Linear")
                }
            }
            Text(issue.title)
                .font(.callout)
                .lineLimit(2)
            if let projectName = issue.projectName {
                Text(projectName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if let worktreeName {
                Label(worktreeName, systemImage: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(issue.isOrphaned ? 0.55 : 1.0)
    }
}

// MARK: - Kanban variant (drag + context menu)

struct KanbanIssueCardView: View {
    let issue: LinearIssue
    let workflowStatesByTeam: WorkflowStatesByTeam
    let worktrees: [Worktree]
    let repositories: [Repository]
    var worktreeName: String?
    let onMoveToStatus: (_ issueId: String, _ statusType: String) -> Void
    let onAssignToWorktree: (_ issue: LinearIssue, _ worktreeId: String) -> Void
    let onRemove: (_ issueId: String) -> Void

    /// Deduplicate workflow states for this issue's team by type.
    /// The "Move to..." menu shows one entry per status type.
    private var movableStates: [LinearWorkflowState] {
        let teamStates = workflowStatesByTeam[issue.teamId] ?? []
        return Dictionary(grouping: teamStates, by: \.type)
            .values
            .compactMap { $0.min(by: { $0.position < $1.position }) }
            .filter { $0.type != issue.statusType }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        IssueCardView(issue: issue, worktreeName: worktreeName)
            .draggable(issue.id)
            .contextMenu {
                Menu("Move to...") {
                    ForEach(movableStates, id: \.type) { state in
                        Button(state.name) {
                            onMoveToStatus(issue.id, state.type)
                        }
                    }
                }
                if !worktrees.isEmpty {
                    Menu("Move to Worktree") {
                        let grouped = repositories.filter { repo in
                            worktrees.contains { $0.repoId == repo.id }
                        }
                        ForEach(grouped) { repo in
                            Section(repo.name) {
                                ForEach(worktrees.filter { $0.repoId == repo.id }) { worktree in
                                    Button(worktree.name) { onAssignToWorktree(issue, worktree.id) }
                                }
                            }
                        }
                        let ungrouped = worktrees.filter { $0.repoId == nil }
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
            }
    }
}
