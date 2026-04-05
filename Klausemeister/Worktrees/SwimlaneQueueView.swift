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
}

struct SwimlaneQueueView: View {
    let role: SwimlaneQueueRole
    let issues: [LinearIssue]
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDrop: ((_ issueId: String) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwimlaneZoneHeader(icon: role.icon, title: role.title, count: issues.count)
            if issues.isEmpty {
                SwimlaneEmptyPlaceholder(label: role.emptyLabel)
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
        .padding(8)
        .frame(minWidth: 160, idealWidth: 200, alignment: .topLeading)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
