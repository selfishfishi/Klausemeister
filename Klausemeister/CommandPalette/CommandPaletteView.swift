// Klausemeister/CommandPalette/CommandPaletteView.swift
import ComposableArchitecture
import SwiftUI

struct CommandPaletteView: View {
    @Bindable var store: StoreOf<CommandPaletteFeature>
    @FocusState private var searchFocused: Bool

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !store.results.isEmpty {
                Divider()
                resultsList
            }
        }
        .frame(width: 560)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onAppear {
            searchFocused = true
            store.send(.onAppear)
        }
        .onKeyPress(.upArrow) { store.send(.moveUp); return .handled }
        .onKeyPress(.downArrow) { store.send(.moveDown); return .handled }
        .onKeyPress(.return) { store.send(.confirmSelection); return .handled }
        .onKeyPress(.escape) { store.send(.dismiss); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Search commands…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.results.enumerated()), id: \.element.id) { _, result in
                        CommandResultRowView(
                            result: result,
                            isSelected: result.id == store.results[safe: store.selectedIndex]?.id,
                            accentColor: themeColors.accentColor
                        ) {
                            store.send(.rowTapped(result.command))
                        }
                        .id(result.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)
            .onChange(of: store.selectedIndex) { _, newIndex in
                if newIndex < store.results.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(store.results[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Result Row (presentation component)

struct CommandResultRowView: View {
    let result: CommandPaletteFeature.State.CommandResult
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                highlightedName
                Spacer()
                categoryBadge
                if let binding = result.currentBinding {
                    Text(binding.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? accentColor.opacity(0.15) : .clear)
    }

    private var highlightedName: some View {
        let name = result.command.displayName
        let offsetSet = Set(result.matchedOffsets)
        var attributed = AttributedString(name)
        for (charOffset, charIndex) in name.indices.enumerated() {
            if offsetSet.contains(charOffset) {
                let attrStart = attributed.index(
                    attributed.startIndex, offsetByCharacters: charOffset
                )
                let attrEnd = attributed.index(afterCharacter: attrStart)
                attributed[attrStart ..< attrEnd].font = .body.bold()
            }
            _ = charIndex // silence unused warning
        }
        return Text(attributed)
            .font(.body)
    }

    private var categoryBadge: some View {
        Text(result.command.category.rawValue.uppercased())
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.fill.quaternary, in: Capsule())
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
