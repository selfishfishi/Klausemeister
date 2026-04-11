// Klausemeister/Worktrees/WorktreeDetailPaneView.swift
import SwiftUI

/// Presentation component rendering a worktree's header (name, branch, repo)
/// and its two detail tabs: the inbox/processing/outbox queue columns, and
/// the libghostty Terminal surface attached to the worktree's tmux session.
/// Shared between the sidebar-routed `WorktreeDetailView` and the Meister
/// inline expansion.
///
/// Takes plain values and closures per CLAUDE.md presentation-component rules.
struct WorktreeDetailPaneView: View {
    let worktree: Worktree
    var activeTab: WorktreeDetailTab = .queue
    var surfaceView: SurfaceView?
    /// When nil, the Queue/Terminal segmented picker is hidden and the pane
    /// renders the queue columns directly. Used by the Meister inline
    /// expansion which does not own a SurfaceStore and always shows the queue.
    var onTabChange: ((WorktreeDetailTab) -> Void)?
    var onRename: ((String) -> Void)?
    var onMarkComplete: () -> Void
    var onReturnToMeister: (String) -> Void
    var onDelete: () -> Void

    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let onTabChange {
                Picker("", selection: Binding(
                    get: { activeTab },
                    set: onTabChange
                )) {
                    Text("Queue").tag(WorktreeDetailTab.queue)
                    Text("Terminal").tag(WorktreeDetailTab.terminal)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                Group {
                    switch activeTab {
                    case .queue:
                        queueColumns
                    case .terminal:
                        WorktreeTerminalTabView(
                            worktree: worktree,
                            surfaceView: surfaceView
                        )
                    }
                }
            } else {
                queueColumns
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                if onRename != nil {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .focused($nameFieldFocused)
                        .onSubmit(commitRename)
                } else {
                    Text(worktree.name)
                        .font(.title2.weight(.semibold))
                }
                if let branch = worktree.currentBranch {
                    Text(branch)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let repoName = worktree.repoName {
                    Text(repoName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .onAppear { draftName = worktree.name }
        .onChange(of: worktree.name) { _, newValue in
            // Sync external updates (e.g. successful rename persisted,
            // rollback on failure) — but don't clobber user's in-progress edit.
            if !nameFieldFocused { draftName = newValue }
        }
    }

    private var queueColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            WorktreeQueueColumn(
                title: "Inbox",
                icon: "tray.and.arrow.down",
                issues: worktree.inbox,
                emptyText: "Drag issues here",
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Processing",
                icon: "gearshape",
                issues: worktree.processing.map { [$0] } ?? [],
                emptyText: "Nothing in progress",
                onMarkComplete: worktree.processing != nil ? onMarkComplete : nil,
                onReturnToMeister: onReturnToMeister
            )

            Divider()

            WorktreeQueueColumn(
                title: "Outbox",
                icon: "tray.and.arrow.up",
                issues: worktree.outbox,
                emptyText: "Completed issues appear here",
                onReturnToMeister: onReturnToMeister
            )
        }
    }

    private func commitRename() {
        guard let onRename else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = worktree.name
            return
        }
        if trimmed == worktree.name { return }
        onRename(trimmed)
    }
}
