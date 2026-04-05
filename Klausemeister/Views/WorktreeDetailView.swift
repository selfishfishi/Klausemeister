// Klausemeister/Views/WorktreeDetailView.swift
import ComposableArchitecture
import SwiftUI

struct WorktreeDetailView: View {
    @Bindable var store: StoreOf<WorktreeFeature>

    var body: some View {
        if let worktreeId = store.selectedWorktreeId,
           let worktree = store.worktrees[id: worktreeId]
        {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(worktree.name)
                            .font(.title2.weight(.semibold))
                        if let branch = worktree.currentBranch {
                            Text(branch)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.send(.confirmDeleteTapped(worktreeId: worktreeId))
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                Divider()

                // Swimlanes
                HStack(alignment: .top, spacing: 0) {
                    // Inbox
                    WorktreeQueueColumn(
                        title: "Inbox",
                        icon: "tray.and.arrow.down",
                        issues: worktree.inbox,
                        emptyText: "Drag issues here",
                        onReturnToMeister: { issueId in
                            store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktreeId))
                        }
                    )

                    Divider()

                    // Outbox
                    WorktreeQueueColumn(
                        title: "Outbox",
                        icon: "tray.and.arrow.up",
                        issues: worktree.outbox,
                        emptyText: "Completed issues appear here",
                        onReturnToMeister: { issueId in
                            store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktreeId))
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .alert($store.scope(state: \.alert, action: \.alert))
        } else {
            ContentUnavailableView(
                "Select a Worktree",
                systemImage: "arrow.triangle.branch",
                description: Text("Choose a worktree from the sidebar or create a new one.")
            )
        }
    }
}

struct WorktreeQueueColumn: View {
    let title: String
    let icon: String
    let issues: [LinearIssue]
    let emptyText: String
    var onReturnToMeister: ((_ issueId: String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text("\(issues.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.fill.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if issues.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(issues, id: \.id) { issue in
                            WorktreeIssueRow(
                                issue: issue,
                                onReturnToMeister: onReturnToMeister.map { callback in
                                    { callback(issue.id) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorktreeIssueRow: View {
    let issue: LinearIssue
    var onReturnToMeister: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(issue.identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(issue.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.quaternary, in: Capsule())
            }
            Text(issue.title)
                .font(.callout)
                .lineLimit(2)
        }
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if let onReturn = onReturnToMeister {
                Button("Return to Meister") {
                    onReturn()
                }
            }
        }
    }
}
