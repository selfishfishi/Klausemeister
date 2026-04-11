import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeSwimlaneView: View {
    @Bindable var store: StoreOf<WorktreeFeature>
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
        HStack(spacing: 8) {
            Text("Worktrees")
                .font(.headline)
            Spacer()
            if store.isCreatingWorktree {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                store.send(.createSheetShown(prefilledRepoId: nil))
            } label: {
                Label("New Worktree", systemImage: "plus")
                    .font(.callout)
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
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .help("Add Repository")
        }
        .padding(12)
    }

    private var swimlanes: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 12) {
                ForEach(store.repositories) { repo in
                    repoSection(repo: repo)
                }
                let ungrouped = store.worktrees.filter { $0.repoId == nil }
                ForEach(ungrouped) { worktree in
                    swimlaneRow(worktree: worktree)
                }
            }
            .padding(12)
        }
    }

    private func repoSection(repo: Repository) -> some View {
        let isCollapsed = store.collapsedRepoIds.contains(repo.id)
        let repoWorktrees = store.worktrees.filter { $0.repoId == repo.id }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = store.send(.repoCollapseToggled(repoId: repo.id))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 8)
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(repo.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isCollapsed {
                            Text("\(repoWorktrees.count)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if !isCollapsed {
                if repoWorktrees.isEmpty {
                    Text("No worktrees yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    ForEach(repoWorktrees) { worktree in
                        swimlaneRow(worktree: worktree)
                    }
                }
            }
        }
    }

    private func swimlaneRow(worktree: Worktree) -> some View {
        let isExpanded = store.expandedWorktreeIdInMeister == worktree.id
        return VStack(alignment: .leading, spacing: 6) {
            SwimlaneRowView(
                worktree: worktree,
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
                },
                isExpanded: isExpanded,
                onToggleExpand: {
                    store.send(.meisterExpansionToggled(worktreeId: worktree.id))
                }
            )

            if isExpanded {
                WorktreeDetailPaneView(
                    worktree: worktree,
                    onRename: { newName in
                        store.send(.renameWorktreeTapped(
                            worktreeId: worktree.id, newName: newName
                        ))
                    },
                    onMarkComplete: {
                        store.send(.markAsCompleteTapped(worktreeId: worktree.id))
                    },
                    onReturnToMeister: { issueId in
                        store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktree.id))
                    },
                    onDelete: {
                        store.send(.confirmDeleteTapped(worktreeId: worktree.id))
                    }
                )
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
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
