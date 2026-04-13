// Klausemeister/WorktreeSwitcher/WorktreeSwitcherView.swift
import ComposableArchitecture
import SwiftUI

struct WorktreeSwitcherView: View {
    @Bindable var store: StoreOf<WorktreeSwitcherFeature>
    @FocusState private var searchFocused: Bool

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            itemList
        }
        .frame(width: 420)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onAppear { searchFocused = true }
        .onKeyPress(.upArrow) { store.send(.moveUp); return .handled }
        .onKeyPress(.downArrow) { store.send(.moveDown); return .handled }
        .onKeyPress(.return) { store.send(.confirmSelection); return .handled }
        .onKeyPress(.escape) { store.send(.dismiss); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = Int(String(press.characters)), digit >= 1, digit <= 9 else {
                return .ignored
            }
            store.send(.numberPressed(digit))
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "np")) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            if press.characters == "n" {
                store.send(.moveDown)
            } else {
                store.send(.moveUp)
            }
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Switch to…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    let filtered = store.filteredItems
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        SwitcherItemRow(
                            item: item,
                            number: index + 1,
                            isSelected: index == store.selectedIndex,
                            accentColor: themeColors.accentColor
                        ) {
                            store.send(.numberPressed(index + 1))
                        }
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)
            .onChange(of: store.selectedIndex) { _, newIndex in
                let filtered = store.filteredItems
                if newIndex < filtered.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Row (presentation component)

struct SwitcherItemRow: View {
    let item: WorktreeSwitcherFeature.SwitcherItem
    let number: Int
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)

                Image(systemName: item.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.body)
                    if let branch = item.branch {
                        Text(branch)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? accentColor.opacity(0.15) : .clear)
    }
}
