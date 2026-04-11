import ComposableArchitecture
import SwiftUI

struct MeisterView: View {
    @Bindable var store: StoreOf<MeisterFeature>
    let worktrees: [Worktree]
    let repositories: [Repository]
    var assignedWorktreeNames: [String: String] = [:]

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            // Header with sync button
            HStack(spacing: 8) {
                Spacer()
                SyncIndicatorMenu(
                    syncStatus: store.syncStatus,
                    onRefresh: { store.send(.refreshTapped) },
                    onReloadMetadata: { store.send(.refreshLinearMetadataTapped) }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Kanban board
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.columns) { column in
                        KanbanColumnView(
                            column: column,
                            workflowStatesByTeam: store.workflowStatesByTeam,
                            worktrees: worktrees,
                            repositories: repositories,
                            assignedWorktreeNames: assignedWorktreeNames,
                            onMoveToStatus: { issueId, statusType in
                                store.send(.moveToStatusTapped(issueId: issueId, targetStatusType: statusType))
                            },
                            onAssignToWorktree: { issue, worktreeId in
                                store.send(.assignIssueToWorktree(issue: issue, worktreeId: worktreeId))
                            },
                            onRemove: { issueId in
                                store.send(.removeIssueTapped(issueId: issueId))
                            },
                            onDrop: { issueId in
                                store.send(.issueDropped(issueId: issueId, onColumnId: column.id))
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { store.send(.onAppear) }
    }
}

// MARK: - Sync Indicator Button

private struct SyncIndicatorMenu: View {
    let syncStatus: MeisterFeature.SyncStatus
    let onRefresh: () -> Void
    let onReloadMetadata: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Menu {
            Button {
                onRefresh()
            } label: {
                Label("Refresh issues", systemImage: "arrow.clockwise")
            }
            Button {
                onReloadMetadata()
            } label: {
                Label("Reload Linear metadata", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            image
                .imageScale(.small)
                .frame(width: 18, height: 18)
        } primaryAction: {
            onRefresh()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(syncStatus == .syncing)
        .help(helpText)
    }

    @ViewBuilder
    private var image: some View {
        switch syncStatus {
        case .idle:
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .tint(themeColors.accentColor)
        case .succeeded:
            Image(systemName: "checkmark")
                .foregroundStyle(themeColors.accentColor)
                .transition(.opacity)
        }
    }

    private var helpText: String {
        switch syncStatus {
        case .idle: "Sync issues with klause label"
        case .syncing: "Syncing..."
        case .succeeded: "Sync complete"
        }
    }
}
