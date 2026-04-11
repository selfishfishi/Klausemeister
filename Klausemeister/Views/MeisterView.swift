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
            // Header with filter + sync
            HStack(spacing: 10) {
                Spacer()
                FilterMenu(
                    hiddenStages: store.hiddenStages,
                    onToggle: { stage in
                        store.send(
                            .stageVisibilityToggled(stage),
                            animation: .smooth(duration: 0.2)
                        )
                    }
                )
                SyncIndicatorMenu(
                    syncStatus: store.syncStatus,
                    onRefresh: { store.send(.refreshTapped) },
                    onReloadMetadata: { store.send(.refreshLinearMetadataTapped) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Kanban board
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(store.visibleColumns) { column in
                        KanbanColumnView(
                            column: column,
                            worktrees: worktrees,
                            repositories: repositories,
                            assignedWorktreeNames: assignedWorktreeNames,
                            onMoveToStatus: { issueId, target in
                                store.send(.moveToStatusTapped(issueId: issueId, target: target))
                            },
                            onAssignToWorktree: { issue, worktreeId in
                                store.send(.assignIssueToWorktree(issue: issue, worktreeId: worktreeId))
                            },
                            onRemove: { issueId in
                                store.send(.removeIssueTapped(issueId: issueId))
                            },
                            onDrop: { issueId in
                                store.send(.issueDropped(issueId: issueId, onColumn: column.id))
                            }
                        )
                        .transition(
                            .scale(scale: 0.85)
                                .combined(with: .opacity)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
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
        .glassEffect(.regular.interactive(), in: Capsule())
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

// MARK: - Filter Menu (Liquid Glass)

/// Dropdown menu letting the user toggle individual `MeisterState` columns
/// on and off. Wrapped in `.glassEffect` to match the Liquid Glass look used
/// for other floating controls in the app. Pure presentation — takes the
/// current hidden set and a toggle callback, no store dependency.
private struct FilterMenu: View {
    let hiddenStages: Set<MeisterState>
    let onToggle: (MeisterState) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Menu {
            ForEach(MeisterState.allCases) { stage in
                Button {
                    onToggle(stage)
                } label: {
                    if hiddenStages.contains(stage) {
                        Text(stage.displayName)
                    } else {
                        Label(stage.displayName, systemImage: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: hiddenStages.isEmpty
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill"
            )
            .imageScale(.small)
            .foregroundStyle(hiddenStages.isEmpty ? .secondary : themeColors.accentColor)
            .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("Filter visible columns")
    }
}
