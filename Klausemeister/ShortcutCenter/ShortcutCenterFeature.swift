// Klausemeister/ShortcutCenter/ShortcutCenterFeature.swift
import ComposableArchitecture
import Foundation

@Reducer
struct ShortcutCenterFeature {
    @ObservableState
    struct State: Equatable {
        var rows: IdentifiedArrayOf<BindingRow> = []
        var filterQuery: String = ""
        var recording: RecordingState?
        var isDirty: Bool = false
        var saveError: String?

        // swiftlint:disable:next nesting
        struct BindingRow: Equatable, Identifiable {
            var id: AppCommand {
                command
            }

            let command: AppCommand
            let defaultBinding: KeyBinding?
            var currentBinding: KeyBinding?
            var hasConflict: Bool = false

            var isModified: Bool {
                currentBinding != defaultBinding
            }
        }

        // swiftlint:disable:next nesting
        struct RecordingState: Equatable {
            let command: AppCommand
        }

        init(keyBindings: [AppCommand: KeyBinding]) {
            rows = IdentifiedArrayOf(uniqueElements: AppCommand.allCases.map { command in
                BindingRow(
                    command: command,
                    defaultBinding: command.defaultBinding,
                    currentBinding: keyBindings[command] ?? command.defaultBinding
                )
            })
        }

        init() {}
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case recordingStarted(AppCommand)
        case recordingStopped
        case keyEventCaptured(KeyBinding)
        case bindingCleared(AppCommand)
        case resetToDefault(AppCommand)
        case resetAllToDefaults
        case saveTapped
        case saveSucceeded
        case saveFailed(String)
        case cancelTapped
        case delegate(Delegate)

        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case bindingsSaved([AppCommand: KeyBinding])
            case dismissed
        }
    }

    nonisolated private enum CancelID {
        case recording
    }

    @Dependency(\.keyBindingsClient) var keyBindingsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .recordingStarted(command):
                state.recording = State.RecordingState(command: command)
                return .run { [keyBindingsClient] send in
                    for await binding in keyBindingsClient.captureNextKeyBinding() {
                        await send(.keyEventCaptured(binding))
                    }
                }
                .cancellable(id: CancelID.recording, cancelInFlight: true)

            case .recordingStopped:
                state.recording = nil
                return .cancel(id: CancelID.recording)

            case let .keyEventCaptured(binding):
                guard let recording = state.recording else { return .none }
                state.rows[id: recording.command]?.currentBinding = binding
                state.recording = nil
                state.isDirty = true
                recomputeConflicts(state: &state)
                return .cancel(id: CancelID.recording)

            case let .bindingCleared(command):
                state.rows[id: command]?.currentBinding = nil
                state.isDirty = true
                recomputeConflicts(state: &state)
                return .none

            case let .resetToDefault(command):
                let defaultBinding = state.rows[id: command]?.defaultBinding
                state.rows[id: command]?.currentBinding = defaultBinding
                state.isDirty = true
                recomputeConflicts(state: &state)
                return .none

            case .resetAllToDefaults:
                for index in state.rows.indices {
                    state.rows[index].currentBinding = state.rows[index].defaultBinding
                }
                state.isDirty = true
                recomputeConflicts(state: &state)
                return .none

            case .saveTapped:
                let overrides = buildOverridesDictionary(from: state)
                return .run { [keyBindingsClient] send in
                    do {
                        try await keyBindingsClient.saveOverrides(overrides)
                        await send(.saveSucceeded)
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case .saveSucceeded:
                let bindings = buildBindingsDictionary(from: state)
                return .send(.delegate(.bindingsSaved(bindings)))

            case let .saveFailed(message):
                state.saveError = message
                return .none

            case .cancelTapped:
                return .send(.delegate(.dismissed))

            case .delegate, .binding:
                return .none
            }
        }
    }

    private func recomputeConflicts(state: inout State) {
        // Clear all conflicts first
        for index in state.rows.indices {
            state.rows[index].hasConflict = false
        }
        // Find duplicate bindings
        var seen: [KeyBinding: [AppCommand]] = [:]
        for row in state.rows {
            guard let binding = row.currentBinding else { continue }
            seen[binding, default: []].append(row.command)
        }
        for (_, commands) in seen where commands.count > 1 {
            for command in commands {
                state.rows[id: command]?.hasConflict = true
            }
        }
    }

    /// Builds the full resolved bindings dict (non-nil only) for the delegate.
    private func buildBindingsDictionary(
        from state: State
    ) -> [AppCommand: KeyBinding] {
        Dictionary(
            uniqueKeysWithValues: state.rows.compactMap { row in
                guard let binding = row.currentBinding else { return nil }
                return (row.command, binding)
            }
        )
    }

    /// Builds the overrides dict for persistence. Includes explicit `nil`
    /// for commands where the user cleared the shortcut (default exists but
    /// user wants none).
    private func buildOverridesDictionary(
        from state: State
    ) -> [AppCommand: KeyBinding?] {
        var overrides: [AppCommand: KeyBinding?] = [:]
        for row in state.rows where row.currentBinding != row.defaultBinding {
            overrides[row.command] = row.currentBinding // nil if cleared
        }
        return overrides
    }
}

// MARK: - Derived State

extension ShortcutCenterFeature.State {
    var filteredRows: [BindingRow] {
        let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return Array(rows) }
        return rows.filter { row in
            row.command.displayName.lowercased().contains(query)
                || (row.currentBinding?.displayString.lowercased().contains(query) ?? false)
                || row.command.category.rawValue.lowercased().contains(query)
        }
    }

    var hasConflicts: Bool {
        rows.contains(where: \.hasConflict)
    }
}
