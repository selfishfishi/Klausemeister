import ComposableArchitecture
import SwiftUI

struct WorktreeSwimlaneView: View {
    @Bindable var store: StoreOf<WorktreeFeature>
    var teams: [LinearTeam] = []

    @Environment(\.themeColors) private var themeColors
    @Environment(\.controlActiveState) private var activeState
    @State private var isPanelVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            swimlanes
                // Gate on both panel visibility (onAppear/onDisappear) and
                // window focus — so animations stop when the window is
                // backgrounded, not just when the panel scrolls off-screen.
                .environment(\.swimlaneAnimating, isPanelVisible && activeState != .inactive)
                .onAppear { isPanelVisible = true }
                .onDisappear { isPanelVisible = false }
        }
        .task { store.send(.onAppear) }
        .alert($store.scope(state: \.alert, action: \.alert))
        .sheet(
            isPresented: Binding(
                get: { store.createSheet != nil },
                set: { newValue in
                    if !newValue { store.send(.createSheetDismissed) }
                }
            )
        ) {
            if let sheetState = store.createSheet {
                CreateWorktreeSheetView(
                    repositories: Array(store.repositories),
                    sheetState: sheetState,
                    onNameChanged: { store.send(.createSheetNameChanged($0)) },
                    onSubmit: { store.send(.createSheetSubmitted) },
                    onCancel: { store.send(.createSheetDismissed) }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Spacer()
            if store.isCreatingWorktree {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                store.send(.addRepoFolderTapped)
            } label: {
                Label("Add Repo", systemImage: "folder.badge.plus")
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .help("Add Repository")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var swimlanes: some View {
        let tints = themeColors.swimlaneRowTints
        return ScrollView(.vertical) {
            LazyVStack(spacing: 12) {
                ForEach(store.repositories) { repo in
                    repoSection(repo: repo, tints: tints)
                }
                ForEach(store.ungroupedWorktrees) { worktree in
                    swimlaneRow(worktree: worktree, tints: tints)
                }
            }
            .padding(12)
        }
    }

    private func repoSection(repo: Repository, tints: [Color]) -> some View {
        let isCollapsed = store.collapsedRepoIds.contains(repo.id)
        let repoWorktrees = store.worktreesByRepo[repo.id] ?? []

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = store.send(.repoCollapseToggled(repoId: repo.id))
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Image(systemName: "folder")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(repo.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                        if isCollapsed {
                            Text("\(repoWorktrees.count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.fill.quaternary, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if !isCollapsed {
                    Button {
                        store.send(.createSheetShown(prefilledRepoId: repo.id))
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New worktree")
                }
                Button {
                    store.send(.removeRepoTapped(repoId: repo.id))
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove repository")
            }
            .padding(.horizontal, 4)

            if !isCollapsed {
                if repoWorktrees.isEmpty {
                    Text("No worktrees yet")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    ForEach(repoWorktrees) { worktree in
                        swimlaneRow(worktree: worktree, tints: tints)
                    }
                }
            }
        }
    }

    /// Stable per-worktree tint: a cheap unicode-scalar sum over the id
    /// ensures the same worktree always lands on the same palette slot,
    /// independent of `store.worktrees` ordering (which isn't guaranteed
    /// stable across fetches, and we can't sort it here without touching
    /// `WorktreeFeature`).
    private func rowTint(for worktree: Worktree, palette: [Color]) -> Color {
        guard !palette.isEmpty else { return themeColors.accentColor }
        let sum = worktree.id.unicodeScalars.reduce(UInt(0)) { $0 &+ UInt($1.value) }
        return palette[Int(sum % UInt(palette.count))]
    }

    private func swimlaneRow(worktree: Worktree, tints: [Color]) -> some View {
        let rowTint = rowTint(for: worktree, palette: tints)

        return SwimlaneRowView(
            worktree: worktree,
            tint: rowTint,
            onDelete: {
                store.send(.confirmDeleteTapped(worktreeId: worktree.id))
            },
            onRemove: {
                store.send(.removeWorktreeTapped(worktreeId: worktree.id))
            },
            onClearInbox: {
                store.send(.clearInboxTapped(worktreeId: worktree.id))
            },
            onClearOutbox: {
                store.send(.clearOutboxTapped(worktreeId: worktree.id))
            },
            onMarkComplete: {
                store.send(.markAsCompleteTapped(worktreeId: worktree.id))
            },
            onReturnToMeister: { issueId in
                store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktree.id))
            },
            onDropToInbox: { issueId in
                store.send(.issueDroppedOnInbox(issueId: issueId, worktreeId: worktree.id))
            },
            onDropToProcessing: { issueId in
                store.send(.issueDroppedOnProcessing(issueId: issueId, worktreeId: worktree.id))
            },
            onDropToOutbox: { issueId in
                store.send(.issueDroppedOnOutbox(issueId: issueId, worktreeId: worktree.id))
            },
            onSelectIssue: { issueId in
                store.send(.queueRowTapped(issueId: issueId))
            },
            onSendSlashCommand: { slashCommand in
                store.send(.sendSlashCommandRequested(
                    worktreeId: worktree.id,
                    slashCommand: slashCommand
                ))
            },
            onMoveIssueStatus: { issueId, target in
                store.send(.moveIssueStatusRequested(issueId: issueId, target: target))
            }
        )
    }
}
