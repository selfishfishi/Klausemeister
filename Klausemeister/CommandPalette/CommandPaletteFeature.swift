// Klausemeister/CommandPalette/CommandPaletteFeature.swift
import ComposableArchitecture
import Foundation
import OSLog

@Reducer
struct CommandPaletteFeature {
    nonisolated private static let log = Logger(
        subsystem: "com.klausemeister", category: "CommandPalette"
    )

    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var results: [CommandResult] = []
        var selectedIndex: Int = 0
        var recentCommands: [AppCommand] = []
        var keyBindings: [AppCommand: KeyBinding] = [:]

        // swiftlint:disable:next nesting
        struct CommandResult: Equatable, Identifiable {
            var id: AppCommand {
                command
            }

            let command: AppCommand
            let score: Int
            /// Character offsets into `command.displayName` for highlight rendering.
            let matchedOffsets: [Int]
            let currentBinding: KeyBinding?
        }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case historyLoaded([AppCommand])
        case moveUp
        case moveDown
        case confirmSelection
        case rowTapped(AppCommand)
        case dismiss
        case delegate(Delegate)

        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case commandInvoked(AppCommand)
            case dismissed
        }
    }

    @Dependency(\.databaseClient) var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                recomputeResults(state: &state)
                return .none

            case .onAppear:
                return .run { send in
                    let history: [AppCommand]
                    do {
                        history = try await databaseClient.fetchCommandHistory()
                    } catch {
                        Self.log.warning(
                            "Failed to load command history: \(error.localizedDescription)"
                        )
                        history = []
                    }
                    await send(.historyLoaded(history))
                }

            case let .historyLoaded(commands):
                state.recentCommands = commands
                recomputeResults(state: &state)
                return .none

            case .moveUp:
                if state.selectedIndex > 0 { state.selectedIndex -= 1 }
                return .none

            case .moveDown:
                if state.selectedIndex < state.results.count - 1 {
                    state.selectedIndex += 1
                }
                return .none

            case .confirmSelection:
                guard state.selectedIndex < state.results.count else { return .none }
                let command = state.results[state.selectedIndex].command
                return invokeCommand(command)

            case let .rowTapped(command):
                return invokeCommand(command)

            case .dismiss:
                return .send(.delegate(.dismissed))

            case .delegate, .binding:
                return .none
            }
        }
    }

    private func invokeCommand(_ command: AppCommand) -> Effect<Action> {
        .run { [databaseClient] send in
            do {
                try await databaseClient.recordCommandUsed(command)
            } catch {
                Self.log.warning(
                    "Failed to record command usage: \(error.localizedDescription)"
                )
            }
            await send(.delegate(.commandInvoked(command)))
        }
    }

    private func recomputeResults(state: inout State) {
        state.selectedIndex = 0
        state.results = Self.computeResults(
            query: state.query,
            recents: state.recentCommands,
            bindings: state.keyBindings
        )
    }

    nonisolated static func computeResults(
        query: String,
        recents: [AppCommand],
        bindings: [AppCommand: KeyBinding]
    ) -> [State.CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let recentSet = Set(recents)
            var results: [State.CommandResult] = recents
                .filter { $0 != .openCommandPalette }
                .map { command in
                    State.CommandResult(
                        command: command,
                        score: Int.max,
                        matchedOffsets: [],
                        currentBinding: bindings[command]
                    )
                }
            for command in AppCommand.allCases where !recentSet.contains(command) {
                if command == .openCommandPalette { continue }
                results.append(State.CommandResult(
                    command: command,
                    score: Int.max - 1,
                    matchedOffsets: [],
                    currentBinding: bindings[command]
                ))
            }
            return results
        }

        var scored: [(result: State.CommandResult, score: Int)] = []
        for command in AppCommand.allCases where command != .openCommandPalette {
            let targets = [command.displayName, command.category.rawValue, command.helpText]
            var bestMatch: FuzzyMatcher.Match?
            for target in targets {
                if let thisMatch = FuzzyMatcher.match(query: trimmed, against: target) {
                    if bestMatch == nil || thisMatch.score > bestMatch!.score {
                        bestMatch = thisMatch
                    }
                }
            }
            guard let matched = bestMatch else { continue }
            let nameMatch = FuzzyMatcher.match(query: trimmed, against: command.displayName)
            scored.append((
                result: State.CommandResult(
                    command: command,
                    score: matched.score,
                    matchedOffsets: nameMatch?.matchedOffsets ?? [],
                    currentBinding: bindings[command]
                ),
                score: matched.score
            ))
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.result)
    }
}
