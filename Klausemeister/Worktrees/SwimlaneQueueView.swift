import SwiftUI

enum SwimlaneQueueRole {
    case inbox
    case outbox

    var title: String {
        switch self {
        case .inbox: "INBOX"
        case .outbox: "OUTBOX"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray.and.arrow.down"
        case .outbox: "tray.and.arrow.up"
        }
    }

    var emptyLabel: String {
        switch self {
        case .inbox: "No queued issues"
        case .outbox: "None completed"
        }
    }

    /// Stage tint for the zone, mirroring the Meister kanban's per-stage
    /// colors: inbox carries Todo's gold, outbox carries In Review's pink.
    var tint: Color {
        switch self {
        case .inbox: MeisterState.todo.tint
        case .outbox: MeisterState.inReview.tint
        }
    }
}

struct SwimlaneQueueView: View {
    let role: SwimlaneQueueRole
    let issues: [LinearIssue]
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDrop: ((_ issueId: String) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        let tint = role.tint
        VStack(alignment: .leading, spacing: 8) {
            SwimlaneZoneHeader(icon: role.icon, title: role.title, count: issues.count, tint: tint)
            if issues.isEmpty {
                SwimlaneEmptyPlaceholder(label: role.emptyLabel, tint: tint)
            } else {
                VStack(spacing: 6) {
                    ForEach(issues, id: \.id) { issue in
                        IssueCardView(issue: issue)
                            .draggable(issue.id)
                            .contextMenu {
                                if let onReturn = onReturnToMeister {
                                    Button("Return to Meister") {
                                        onReturn(issue.id)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 160, idealWidth: 200, alignment: .topLeading)
        .glassPanel(tint: tint, cornerRadius: swimlaneGlassCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                .stroke(tint.opacity(isTargeted ? 0.7 : 0), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let issueId = items.first, let onDrop else { return false }
            onDrop(issueId)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}
