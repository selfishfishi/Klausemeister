import SwiftUI

struct KanbanColumnView: View {
    let column: MeisterFeature.KanbanColumn
    let workflowStates: [LinearWorkflowState]
    let onMoveToStatus: (_ issueId: String, _ statusId: String) -> Void
    let onRemove: (_ issueId: String) -> Void
    let onDrop: (_ issueId: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(column.name.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(column.issues.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(column.issues, id: \.id) { issue in
                        KanbanIssueCardView(
                            issue: issue,
                            workflowStates: workflowStates,
                            onMoveToStatus: onMoveToStatus,
                            onRemove: onRemove
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 200, idealWidth: 240)
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            guard let issueId = items.first else { return false }
            onDrop(issueId)
            return true
        }
    }
}
