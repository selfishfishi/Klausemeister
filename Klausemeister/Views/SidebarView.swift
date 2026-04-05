import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 0) {
            tabList
            Divider()
            newTabButton
        }
        .frame(width: 220)
    }

    private var tabList: some View {
        List(selection: Binding(
            get: { store.activeTabID },
            set: { id in
                if let id { store.send(.tabSelected(id)) }
            }
        )) {
            ForEach(store.tabs) { tab in
                SidebarTabRow(
                    title: tab.title,
                    isActive: tab.id == store.activeTabID,
                    onClose: { store.send(.closeTabButtonTapped(tab.id)) }
                )
                .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
    }

    private var newTabButton: some View {
        Button {
            store.send(.newTabButtonTapped)
        } label: {
            Label("New Tab", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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
