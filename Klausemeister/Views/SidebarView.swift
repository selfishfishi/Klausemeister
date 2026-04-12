import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        List {
            // Meister item
            Button {
                store.send(.meisterTapped)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "squares.leading.rectangle")
                        .foregroundStyle(.secondary)
                    Text("Meister")
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .listRowBackground(
                store.showMeister
                    ? RoundedRectangle(cornerRadius: 6)
                    .fill(themeColors.accentColor.opacity(0.18))
                    : nil
            )

            Section {
                ForEach(store.scope(state: \.worktree, action: \.worktree).worktrees) { worktree in
                    SidebarWorktreeRow(
                        worktree: worktree,
                        isSelected: store.worktree.selectedWorktreeId == worktree.id,
                        onSelect: {
                            store.send(.worktree(.worktreeSelected(worktree.id)))
                        },
                        onDelete: {
                            store.send(.worktree(.confirmDeleteTapped(worktreeId: worktree.id)))
                        }
                    )
                }
            } header: {
                Text("Worktrees")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                SidebarLinearStatusView(store: store)
            }
        }
    }
}

struct SidebarWorktreeRow: View {
    let worktree: Worktree
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @Environment(\.themeColors) private var themeColors
    @State private var isHovering = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(worktree.name)
                        .lineLimit(1)
                    if let branch = worktree.currentBranch {
                        Text(branch)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if let repoName = worktree.repoName {
                        Text(repoName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let stats = worktree.gitStats, !stats.isEmpty {
                        GitStatsLineView(stats: stats)
                    }
                }
                Spacer()
                if worktree.totalIssueCount > 0 {
                    Text("\(worktree.totalIssueCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.fill.quaternary, in: Capsule())
                }
                if isHovering {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                .fill(themeColors.accentColor.opacity(0.18))
                : nil
        )
        .onHover { hovering in isHovering = hovering }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Linear Connection Status

struct SidebarLinearStatusView: View {
    let store: StoreOf<AppFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        let authState = store.linearAuth

        HStack(spacing: 6) {
            switch authState.status {
            case .unauthenticated:
                Button {
                    store.send(.linearAuth(.loginButtonTapped))
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text("Connect to Linear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

            case .authenticating, .fetchingTeams:
                ProgressView()
                    .controlSize(.mini)
                    .tint(themeColors.accentColor)
                Text(authState.status == .fetchingTeams ? "Loading teams..." : "Connecting...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

            case .teamSelection:
                Circle()
                    .fill(themeColors.accentColor.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text("Select teams...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .authenticated:
                Circle()
                    .fill(themeColors.accentColor)
                    .frame(width: 6, height: 6)
                if let user = authState.user {
                    Text(user.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.send(.linearAuth(.logoutButtonTapped))
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Disconnect from Linear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .task { store.send(.linearAuth(.onAppear)) }
    }
}
