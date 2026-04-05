import SwiftUI

struct IssueCardView: View {
    let issue: LinearIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Kanban variant (drag + context menu)

struct KanbanIssueCardView: View {
    let issue: LinearIssue
    let workflowStates: [LinearWorkflowState]
    let worktrees: [Worktree]
    let repositories: [Repository]
    let onMoveToStatus: (_ issueId: String, _ statusId: String) -> Void
    let onAssignToWorktree: (_ issue: LinearIssue, _ worktreeId: String) -> Void
    let onRemove: (_ issueId: String) -> Void

    var body: some View {
        IssueCardView(issue: issue)
            .draggable(issue.id)
            .contextMenu {
                Menu("Move to...") {
                    ForEach(workflowStates.filter { $0.id != issue.statusId }) { state in
                        Button(state.name) {
                            onMoveToStatus(issue.id, state.id)
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
                                ForEach(worktrees.filter { $0.repoId == repo.id }) { wt in
                                    Button(wt.name) { onAssignToWorktree(issue, wt.id) }
                                }
                            }
                        }
                        let ungrouped = worktrees.filter { $0.repoId == nil }
                        if !ungrouped.isEmpty {
                            if !grouped.isEmpty { Divider() }
                            ForEach(ungrouped) { wt in
                                Button(wt.name) { onAssignToWorktree(issue, wt.id) }
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
