import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeSwimlaneView: View {
    @Bindable var store: StoreOf<WorktreeFeature>

    @Environment(\.themeColors) private var themeColors
    @State private var isPanelVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            swimlanes
                .environment(\.swimlaneAnimating, isPanelVisible)
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
                    onRepoChanged: { store.send(.createSheetRepoChanged(repoId: $0)) },
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
                store.send(.createSheetShown(prefilledRepoId: nil))
            } label: {
                Label("New Worktree", systemImage: "plus")
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .help("New Worktree")
            .disabled(store.repositories.isEmpty)
            Button {
                openRepoFolderPicker()
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
        // Compute the per-render palette once so row tint lookups don't
        // re-allocate the Set/Array for each worktree in the ForEach.
        let tints = themeColors.swimlaneRowTints
        return ScrollView(.vertical) {
            LazyVStack(spacing: 12) {
                ForEach(store.repositories) { repo in
                    repoSection(repo: repo, tints: tints)
                }
                let ungrouped = store.worktrees.filter { $0.repoId == nil }
                ForEach(ungrouped) { worktree in
                    swimlaneRow(worktree: worktree, tints: tints)
                }
            }
            .padding(12)
        }
    }

    private func repoSection(repo: Repository, tints: [Color]) -> some View {
        let isCollapsed = store.collapsedRepoIds.contains(repo.id)
        let repoWorktrees = store.worktrees.filter { $0.repoId == repo.id }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = store.send(.repoCollapseToggled(repoId: repo.id))
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Image(systemName: "folder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(repo.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .tracking(0.3)
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
                    AddWorktreeInlineButton { name in
                        store.send(.createWorktreeTapped(
                            repoId: repo.id, name: name
                        ))
                    }
                }
                Menu {
                    Button {
                        store.send(.syncRepo(repoId: repo.id))
                    } label: {
                        Label("Refresh worktrees", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.send(.confirmDeleteRepoTapped(repoId: repo.id))
                    } label: {
                        Label("Remove Repository", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
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
            }
        )
    }

    private func openRepoFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository folder"
        panel.prompt = "Add Repository"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                store.send(.addRepoFolderSelected(url))
            }
        }
    }
}
