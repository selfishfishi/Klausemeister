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
    let onMoveToStatus: (_ issueId: String, _ statusId: String) -> Void
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
                Divider()
                Button("Remove from board", role: .destructive) {
                    onRemove(issue.id)
                }
            }
    }
}
