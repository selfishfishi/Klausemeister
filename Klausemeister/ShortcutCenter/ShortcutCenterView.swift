// Klausemeister/ShortcutCenter/ShortcutCenterView.swift
import ComposableArchitecture
import SwiftUI

struct ShortcutCenterView: View {
    @Bindable var store: StoreOf<ShortcutCenterFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            shortcutList
            Divider()
            footer
        }
        .frame(width: 580, height: 520)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Filter shortcuts…", text: $store.filterQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
    }

    // MARK: - Shortcut List

    private var shortcutList: some View {
        let grouped = Dictionary(
            grouping: store.filteredRows,
            by: \.command.category
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(AppCommand.Category.allCases, id: \.self) { category in
                    if let categoryRows = grouped[category], !categoryRows.isEmpty {
                        sectionHeader(category)
                        ForEach(categoryRows, id: \.command) { row in
                            ShortcutRowView(
                                row: row,
                                isRecording: store.recording?.command == row.command,
                                accentColor: themeColors.accentColor,
                                onStartRecording: {
                                    store.send(.recordingStarted(row.command))
                                },
                                onClear: {
                                    store.send(.bindingCleared(row.command))
                                },
                                onReset: {
                                    store.send(.resetToDefault(row.command))
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func sectionHeader(_ category: AppCommand.Category) -> some View {
        Text(category.rawValue.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = store.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Button("Reset All") {
                    store.send(.resetAllToDefaults)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    store.send(.cancelTapped)
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    store.send(.saveTapped)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.isDirty || store.hasConflicts)
            }
        }
        .padding(16)
    }
}

// MARK: - Shortcut Row (presentation component)

struct ShortcutRowView: View {
    let row: ShortcutCenterFeature.State.BindingRow
    let isRecording: Bool
    let accentColor: Color
    let onStartRecording: () -> Void
    let onClear: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.command.displayName)
                    .font(.body)
                Text(row.command.helpText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if row.isModified {
                Button(action: onReset) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }

            KeyRecorderCell(
                binding: row.currentBinding,
                isRecording: isRecording,
                hasConflict: row.hasConflict,
                accentColor: accentColor,
                onStartRecording: onStartRecording,
                onClear: onClear
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - Key Recorder Cell (presentation component)

struct KeyRecorderCell: View {
    let binding: KeyBinding?
    let isRecording: Bool
    let hasConflict: Bool
    let accentColor: Color
    let onStartRecording: () -> Void
    let onClear: () -> Void

    var body: some View {
        Button(action: isRecording ? {} : onStartRecording) {
            Group {
                if isRecording {
                    Text("Type shortcut…")
                        .foregroundStyle(accentColor)
                } else if let binding {
                    Text(binding.displayString)
                        .foregroundStyle(hasConflict ? .red : .primary)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.fill.quaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isRecording ? accentColor : .clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if binding != nil {
                Button("Clear Shortcut") { onClear() }
            }
        }
    }
}
