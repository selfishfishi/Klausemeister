import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
struct StatusBarFeature {
    @ObservableState
    struct State: Equatable {
        var errors: IdentifiedArrayOf<StatusError> = []
        var isSyncing: Bool = false
        var copiedConfirmationVisible: Bool = false
        var isErrorDetailExpanded: Bool = false
    }

    struct StatusError: Equatable, Identifiable {
        let id: UUID
        let source: Source
        let message: String
        let teamKey: String?

        init(id: UUID, source: Source, message: String, teamKey: String? = nil) {
            self.id = id
            self.source = source
            self.message = message
            self.teamKey = teamKey
        }
    }

    struct TeamFailureInfo: Equatable {
        let teamKey: String
        let message: String
    }

    enum Source: Equatable {
        case sync
        case meister
        case worktree
        case linearAuth
        case mcpServer
    }

    enum Action: Equatable {
        case errorReported(source: Source, message: String)
        case teamErrorsReported([TeamFailureInfo])
        case errorClearedForSource(Source)
        case syncStateChanged(Bool)
        case dismissTapped
        case dismissError(id: UUID)
        case copyTapped
        case copiedConfirmationTimerEnded
        case errorDetailToggled
    }

    nonisolated private enum CancelID {
        case copyConfirmation
    }

    static let copyConfirmationDuration: Duration = .milliseconds(1200)

    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .errorReported(source, message):
                state.errors.append(StatusError(
                    id: uuid(), source: source, message: message
                ))
                return .none

            case let .teamErrorsReported(failures):
                // Clear previous sync team errors, then add fresh ones
                state.errors.removeAll { $0.source == .sync && $0.teamKey != nil }
                for failure in failures {
                    state.errors.append(StatusError(
                        id: uuid(), source: .sync,
                        message: failure.message, teamKey: failure.teamKey
                    ))
                }
                return .none

            case let .errorClearedForSource(source):
                state.errors.removeAll { $0.source == source }
                if state.errors.isEmpty {
                    state.isErrorDetailExpanded = false
                }
                return .none

            case let .syncStateChanged(isSyncing):
                state.isSyncing = isSyncing
                return .none

            case .dismissTapped:
                state.errors.removeAll()
                state.copiedConfirmationVisible = false
                state.isErrorDetailExpanded = false
                return .cancel(id: CancelID.copyConfirmation)

            case let .dismissError(errorId):
                state.errors.remove(id: errorId)
                if state.errors.isEmpty {
                    state.isErrorDetailExpanded = false
                }
                return .none

            case .copyTapped:
                guard !state.errors.isEmpty else { return .none }
                state.copiedConfirmationVisible = true
                return .run { [pasteboard, clock, text = state.detailText] send in
                    await pasteboard.setString(text)
                    try await clock.sleep(for: Self.copyConfirmationDuration)
                    await send(.copiedConfirmationTimerEnded)
                }
                .cancellable(id: CancelID.copyConfirmation, cancelInFlight: true)

            case .copiedConfirmationTimerEnded:
                state.copiedConfirmationVisible = false
                return .none

            case .errorDetailToggled:
                state.isErrorDetailExpanded.toggle()
                return .none
            }
        }
    }
}

// MARK: - Computed Properties

extension StatusBarFeature.State {
    /// Single-line summary for the 28pt bar.
    var summaryMessage: String? {
        guard !errors.isEmpty else { return nil }
        if errors.count == 1 {
            let err = errors[0]
            if let key = err.teamKey {
                return "\(key): \(err.message)"
            }
            return err.message
        }
        let syncTeamErrors = errors.filter { $0.source == .sync && $0.teamKey != nil }
        if syncTeamErrors.count == errors.count {
            let keys = syncTeamErrors.compactMap(\.teamKey)
            return "Sync failed for \(keys.count) teams: \(keys.joined(separator: ", "))"
        }
        return "\(errors.count) errors"
    }

    /// Full copyable text with all error details.
    var detailText: String {
        errors.map { error in
            if let key = error.teamKey {
                return "[\(key)] \(error.message)"
            }
            return error.message
        }.joined(separator: "\n")
    }
}
