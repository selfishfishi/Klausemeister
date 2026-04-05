import SwiftUI

struct SwimlaneProcessingZoneView: View {
    let issue: LinearIssue?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwimlaneZoneHeader(icon: "gearshape", title: "PROCESSING", count: issue != nil ? 1 : 0)
            if let issue {
                activeCard(issue)
            } else {
                SwimlaneEmptyPlaceholder(label: "Nothing in progress")
            }
        }
        .padding(8)
        .frame(minWidth: 160, idealWidth: 200, alignment: .topLeading)
    }

    private func activeCard(_ issue: LinearIssue) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(themeColors.accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)
            IssueCardView(issue: issue)
        }
        .background(themeColors.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
