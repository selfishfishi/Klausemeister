import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        List(selection: Binding(
            get: { store.showMeister ? nil : store.activeTabID },
            set: { id in
                if let id { store.send(.tabSelected(id)) }
            }
        )) {
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
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .listRowBackground(
                store.showMeister
                    ? RoundedRectangle(cornerRadius: 6).fill(.selection)
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
                HStack {
                    Text("Worktrees")
                    Spacer()
                    Button {
                        store.send(.worktree(.createWorktreeTapped))
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Terminals") {
                ForEach(store.tabs) { tab in
                    SidebarTabRow(
                        title: tab.title,
                        isActive: tab.id == store.activeTabID,
                        onClose: { store.send(.closeTabButtonTapped(tab.id)) }
                    )
                    .tag(tab.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    store.send(.newTabButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

struct SidebarWorktreeRow: View {
    let worktree: Worktree
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

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
                    if let repoName = worktree.repoName {
                        Text(repoName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 6).fill(.selection)
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

struct SidebarTabRow: View {
    let title: String
    let isActive: Bool
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
            Spacer()
            if isHovering {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
