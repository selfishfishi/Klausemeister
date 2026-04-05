import ComposableArchitecture
import SwiftUI

struct WorktreeSwimlaneView: View {
    @Bindable var store: StoreOf<WorktreeFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            swimlanes
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Worktrees")
                .font(.headline)
            Spacer()
            TextField("New worktree...", text: $store.newWorktreeName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit { store.send(.createWorktreeTapped) }
            if store.isCreatingWorktree {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var swimlanes: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(store.worktrees) { worktree in
                    WorktreeLaneView(
                        worktree: worktree,
                        onDelete: {
                            store.send(.deleteWorktreeTapped(worktreeId: worktree.id))
                        }
                    )
                }
            }
            .padding(12)
        }
    }
}

struct WorktreeLaneView: View {
    let worktree: Worktree
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text(worktree.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Menu {
                    Button("Delete worktree", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                queueSection(title: "INBOX", issues: worktree.inbox)
                if !worktree.outbox.isEmpty {
                    queueSection(title: "OUTBOX", issues: worktree.outbox)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 200, idealWidth: 240)
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func queueSection(title: String, issues: [LinearIssue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(issues.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            ForEach(issues, id: \.id) { issue in
                WorktreeIssueCardView(issue: issue)
            }
        }
    }
}

struct WorktreeIssueCardView: View {
    let issue: LinearIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(issue.title)
                .font(.callout)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
