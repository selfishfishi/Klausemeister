// Klausemeister/Worktrees/WorktreeDetailPaneView.swift
import SwiftUI

/// Presentation component rendering a worktree's header (name, branch, repo)
/// and its inbox/processing/outbox queue columns. Shared between the
/// sidebar-routed `WorktreeDetailView` and the Meister inline expansion.
///
/// Takes plain values and closures per CLAUDE.md presentation-component rules.
struct WorktreeDetailPaneView: View {
    let worktree: Worktree
    var onRename: ((String) -> Void)?
    var onMarkComplete: () -> Void
    var onReturnToMeister: (String) -> Void
    var onDelete: () -> Void

    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            Divider()

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
