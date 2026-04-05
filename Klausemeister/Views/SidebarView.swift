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
