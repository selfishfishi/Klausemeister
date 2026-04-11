// Klausemeister/Views/WorktreeDetailView.swift
import ComposableArchitecture
import SwiftUI

struct WorktreeDetailView: View {
    @Bindable var store: StoreOf<WorktreeFeature>
    let surfaceStore: SurfaceStore

    var body: some View {
        Group {
            if let worktreeId = store.selectedWorktreeId,
               let worktree = store.worktrees[id: worktreeId]
            {
                WorktreeDetailPaneView(
                    worktree: worktree,
                    activeTab: store.activeDetailTab,
                    surfaceView: surfaceStore.surface(for: worktreeId),
                    onTabChange: { tab in
                        store.send(.detailTabSelected(tab))
                    },
                    onRename: { newName in
                        store.send(.renameWorktreeTapped(worktreeId: worktreeId, newName: newName))
                    },
                    onMarkComplete: {
                        store.send(.markAsCompleteTapped(worktreeId: worktreeId))
                    },
                    onReturnToMeister: { issueId in
                        store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktreeId))
                    },
                    onDelete: {
                        store.send(.confirmDeleteTapped(worktreeId: worktreeId))
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Select a Worktree",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Choose a worktree from the sidebar or create a new one.")
                )
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

struct WorktreeQueueColumn: View {
    let title: String
    let icon: String
    let issues: [LinearIssue]
    let emptyText: String
    var onMarkComplete: (() -> Void)?
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
                                onMarkComplete: issue.id == issues.first?.id ? onMarkComplete : nil,
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
    var onMarkComplete: (() -> Void)?
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
            if onMarkComplete != nil || onReturnToMeister != nil {
                HStack(spacing: 8) {
                    if let onMarkComplete {
                        Button("Mark as Done", action: onMarkComplete)
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if let onReturnToMeister {
                        Button("Return to Meister", action: onReturnToMeister)
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if let onMarkComplete {
                Button("Mark as Done") { onMarkComplete() }
            }
            if let onReturn = onReturnToMeister {
                Button("Return to Meister") {
                    onReturn()
                }
            }
        }
    }
}
