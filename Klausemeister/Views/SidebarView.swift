import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        List {
            // Meister item
            Button {
                store.send(.showMeister)
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
                ForEach(store.worktree.repositories) { repo in
                    sidebarRepoSection(repo: repo)
                }
                let ungrouped = store.worktree.worktrees.filter { $0.repoId == nil }
                ForEach(ungrouped) { worktree in
                    sidebarWorktreeRow(worktree)
                }
            } header: {
                HStack {
                    Text("Worktrees")
                    Spacer()
                    Button {
                        store.send(.worktree(.refreshWorktreeInfo))
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh branches and stats")
                }
                .padding(.trailing, 8)
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

    private func sidebarRepoSection(repo: Repository) -> some View {
        let isExpanded = Binding(
            get: { !store.worktree.collapsedRepoIds.contains(repo.id) },
            set: { _ in store.send(.worktree(.repoCollapseToggled(repoId: repo.id))) }
        )
        let repoWorktrees = store.worktree.worktrees.filter { $0.repoId == repo.id }

        return DisclosureGroup(isExpanded: isExpanded) {
            ForEach(repoWorktrees) { worktree in
                sidebarWorktreeRow(worktree)
            }
        } label: {
            Label(repo.name, systemImage: "folder")
                .foregroundStyle(.secondary)
        }
    }

    private func sidebarWorktreeRow(_ worktree: Worktree) -> some View {
        SidebarWorktreeRow(
            worktree: worktree,
            isSelected: store.worktree.selectedWorktreeId == worktree.id,
            onSelect: {
                store.send(.worktree(.worktreeSelected(worktree.id)))
            },
            onDelete: {
                store.send(.worktree(.removeWorktreeTapped(worktreeId: worktree.id)))
            }
        )
    }
}

struct SidebarWorktreeRow: View {
    let worktree: Worktree
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @Environment(\.themeColors) private var themeColors
    @Environment(\.keyBindings) private var bindings
    @State private var isHovering = false

    private var shimmerPaletteColors: [Color] {
        [1, 2, 3, 4, 5, 6].compactMap { idx in
            guard idx < themeColors.palette.count else { return nil }
            return Color(hexString: themeColors.palette[idx])
        }
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 6) {
                WorktreeStatusDot(
                    meisterStatus: worktree.meisterStatus,
                    claudeStatus: worktree.claudeStatus
                )
                VStack(alignment: .leading, spacing: 3) {
                    if worktree.isMeisterWorking {
                        ShimmerText(
                            text: worktree.name,
                            cycleColors: shimmerPaletteColors,
                            baseColor: themeColors.accentColor,
                            phaseSeed: worktree.id
                        )
                    } else {
                        Text(worktree.name)
                            .lineLimit(1)
                    }
                    if let processing = worktree.processing {
                        Text(processing.identifier)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .help("\(processing.identifier) · \(processing.title)")
                    } else if let branch = worktree.currentBranch {
                        Text(branch)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let stats = worktree.gitStats, !stats.isEmpty {
                        GitStatsLineView(stats: stats)
                    }
                    if let narration = sidebarNarrationText {
                        ActivityMarquee(text: narration)
                    } else if let toolName = sidebarToolName {
                        Text(toolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
        .padding(.vertical, 7)
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
            .keyboardShortcut(for: .deleteWorktree, in: bindings)
        }
    }

    /// Long-form narration shown as a scrolling marquee. Priority:
    /// 1. `reportActivity` — live narration (60s TTL)
    /// 2. `reportProgress` — step-boundary label (cleared on idle)
    /// Returns nil when only the bare tool name is available — those use
    /// the static `sidebarToolName` fallback below.
    private var sidebarNarrationText: String? {
        if let text = worktree.claudeActivityText, !text.isEmpty { return text }
        if let text = worktree.claudeStatusText, !text.isEmpty { return text }
        return nil
    }

    /// Hook-written tool name (e.g. "Bash", "Grep") — short enough to render
    /// as plain truncated text rather than a marquee.
    private var sidebarToolName: String? {
        if case let .working(tool) = worktree.claudeStatus,
           let tool, !tool.isEmpty
        {
            return tool
        }
        return nil
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
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Disconnect from Linear")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .task { store.send(.linearAuth(.onAppear)) }
    }
}
