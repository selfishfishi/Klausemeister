// Klausemeister/Views/WorktreeDetailView.swift
import ComposableArchitecture
import SwiftUI

struct WorktreeDetailView: View {
    @Bindable var store: StoreOf<WorktreeFeature>
    let surfaceStore: SurfaceStore
    var teamsByID: [String: LinearTeam] = [:]

    @Environment(\.themeColors) private var themeColors

    private var showTeamBadges: Bool {
        !teamsByID.isEmpty
    }

    var body: some View {
        Group {
            if let worktreeId = store.selectedWorktreeId,
               let worktree = store.worktrees[id: worktreeId]
            {
                let cachedTeamsByID = teamsByID
                WorktreeDetailPaneView(
                    worktree: worktree,
                    showBoardOverlay: store.showBoardOverlay,
                    surfaceView: surfaceStore.surface(for: worktreeId),
                    teamFor: showTeamBadges ? { issue in
                        guard let team = cachedTeamsByID[issue.teamId] else { return nil }
                        return (key: team.key, tint: themeColors.teamTint(colorIndex: team.colorIndex))
                    } : nil,
                    onMarkComplete: {
                        store.send(.markAsCompleteTapped(worktreeId: worktreeId))
                    },
                    onReturnToMeister: { issueId in
                        store.send(.issueReturnedToMeister(issueId: issueId, worktreeId: worktreeId))
                    },
                    onRowTapped: { issueId in
                        store.send(.queueRowTapped(issueId: issueId))
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    store.send(.boardOverlayToggled)
                } label: {
                    Image(systemName: store.showBoardOverlay
                        ? "terminal"
                        : "list.bullet.rectangle")
                }
                .help(store.showBoardOverlay ? "Hide Board" : "Show Board")
            }
        }
        .tint(themeColors.accentColor)
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

struct WorktreeQueueColumn: View {
    let title: String
    let icon: String
    let issues: [LinearIssue]
    let emptyText: String
    var teamFor: ((_ issue: LinearIssue) -> (key: String, tint: Color)?)?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onRowTapped: ((_ issueId: String) -> Void)?

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
                            let teamInfo = teamFor?(issue)
                            WorktreeIssueRow(
                                issue: issue,
                                teamKey: teamInfo?.key,
                                teamTint: teamInfo?.tint,
                                onMarkComplete: issue.id == issues.first?.id ? onMarkComplete : nil,
                                onReturnToMeister: onReturnToMeister.map { callback in
                                    { callback(issue.id) }
                                },
                                onRowTapped: onRowTapped.map { callback in
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
    var teamKey: String?
    var teamTint: Color?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: (() -> Void)?
    var onRowTapped: (() -> Void)?

    @Environment(\.keyBindings) private var bindings

    var body: some View {
        Button {
            onRowTapped?()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onMarkComplete {
                Button("Mark as Done") { onMarkComplete() }
                    .keyboardShortcut(for: .markIssueDone, in: bindings)
            }
            if let onReturn = onReturnToMeister {
                Button("Return to Meister") {
                    onReturn()
                }
                .keyboardShortcut(for: .returnIssueToMeister, in: bindings)
            }
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let teamKey, let teamTint {
                    Text(teamKey)
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(teamTint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(teamTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
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
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
