import AppKit
import SwiftUI

struct TicketInspectorView: View {
    enum ViewState: Equatable {
        case empty
        case loading
        case error(String)
        case loaded(InspectorTicketDetail)
    }

    let state: ViewState
    var onOpenLinear: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var onOpenPR: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            .regular.tint(themeColors.accentColor.opacity(0.04)),
            in: Rectangle()
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if case let .loaded(detail) = state, let url = URL(string: detail.url) {
                Button {
                    onOpenLinear(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Linear")
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.fill.tertiary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close inspector")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .empty:
            placeholder("Select an item to inspect")
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading ticket…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .error(message):
            errorView(message)
        case let .loaded(detail):
            loadedView(detail)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedView(_ detail: InspectorTicketDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection(detail)
                descriptionSection(detail)
                if !detail.attachedPRs.isEmpty {
                    prSection(detail.attachedPRs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerSection(_ detail: InspectorTicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail.title)
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                statusPill(detail.status)
                if let project = detail.projectName {
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(_ detail: InspectorTicketDetail) -> some View {
        if let markdown = detail.descriptionMarkdown, !markdown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Description")
                MarkdownTextView(markdown: markdown)
                    .textSelection(.enabled)
            }
        }
    }

    private func prSection(_ prs: [AttachedPullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Pull Requests")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(prs) { attachment in
                    prRow(attachment)
                }
            }
        }
    }

    private func prRow(_ attachment: AttachedPullRequest) -> some View {
        Button {
            if let url = URL(string: attachment.url) {
                onOpenPR(url)
            }
        } label: {
            HStack(spacing: 6) {
                prStateIcon(attachment.state)
                    .foregroundStyle(prColor(attachment.state))
                if let number = attachment.number {
                    Text("#\(number)")
                        .foregroundStyle(prColor(attachment.state))
                }
                if let repo = attachment.repo {
                    Text(repo)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(attachment.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
            .font(.caption)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func statusPill(_ status: InspectorTicketStatus) -> some View {
        Text(status.name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(statusColor(status.type).opacity(0.18))
            )
            .foregroundStyle(statusColor(status.type))
    }

    private func statusColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "started": blueColor
        case "completed": themeColors.accentColor
        case "canceled": redColor
        case "unstarted", "backlog", "triage": .secondary
        default: .secondary
        }
    }

    private func prStateIcon(_ state: AttachedPullRequest.State) -> Image {
        switch state {
        case .merged: Image(systemName: "arrow.triangle.merge")
        case .open: Image(systemName: "arrow.triangle.pull")
        case .draft: Image(systemName: "pencil.circle")
        case .closed: Image(systemName: "xmark.circle")
        case .unknown: Image(systemName: "questionmark.circle")
        }
    }

    private func prColor(_ state: AttachedPullRequest.State) -> Color {
        switch state {
        case .open: blueColor
        case .merged: magentaColor
        case .closed: redColor
        case .draft, .unknown: .secondary
        }
    }

    private var blueColor: Color {
        Color(hexString: themeColors.palette[4])
    }

    private var redColor: Color {
        Color(hexString: themeColors.palette[1])
    }

    private var magentaColor: Color {
        Color(hexString: themeColors.palette[5])
    }
}

#Preview("loaded") {
    TicketInspectorView(state: .loaded(InspectorTicketDetail(
        id: "x",
        identifier: "KLA-188",
        title: "TicketInspectorView — presentation for Linear ticket detail",
        descriptionMarkdown: """
        Presentation-only SwiftUI view that renders an `InspectorTicketDetail`.

        **Scope**: sections, states, theme-aware colors.
        """,
        url: "https://linear.app/example/issue/KLA-188",
        projectName: "The Inspector",
        projectId: "p1",
        status: InspectorTicketStatus(id: "s1", name: "In Progress", type: "started"),
        attachedPRs: [
            AttachedPullRequest(
                id: "a1", url: "https://github.com/selfishfishi/Klausemeister/pull/138",
                title: "Scaffold Inspector sidebar with Cmd+L toggle",
                number: 138, repo: "selfishfishi/Klausemeister", state: .merged
            ),
            AttachedPullRequest(
                id: "a2", url: "https://github.com/selfishfishi/Klausemeister/pull/140",
                title: "Fetch Linear ticket detail + attached PRs",
                number: 140, repo: "selfishfishi/Klausemeister", state: .open
            )
        ]
    )))
    .frame(width: 340, height: 500)
    .environment(\.themeColors, AppTheme.darkMedium.colors)
}

#Preview("loading") {
    TicketInspectorView(state: .loading)
        .frame(width: 340, height: 500)
        .environment(\.themeColors, AppTheme.darkMedium.colors)
}

#Preview("error") {
    TicketInspectorView(state: .error("Could not reach Linear. Check your connection."))
        .frame(width: 340, height: 500)
        .environment(\.themeColors, AppTheme.darkMedium.colors)
}

#Preview("empty") {
    TicketInspectorView(state: .empty)
        .frame(width: 340, height: 500)
        .environment(\.themeColors, AppTheme.darkMedium.colors)
}
