import ComposableArchitecture
import Foundation

@Reducer
struct StatusBarFeature {
    @ObservableState
    struct State: Equatable {
        var activeError: StatusError?
        var isSyncing: Bool = false
        var copiedConfirmationVisible: Bool = false
    }

    struct StatusError: Equatable, Identifiable {
        let id: UUID
        let source: Source
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
        case errorClearedForSource(Source)
        case syncStateChanged(Bool)
        case dismissTapped
        case copyTapped
        case copiedConfirmationTimerEnded
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
                state.activeError = StatusError(
                    id: uuid(),
                    source: source,
                    message: message
                )
                return .none

            case let .errorClearedForSource(source):
                if state.activeError?.source == source {
                    state.activeError = nil
                }
                return .none

            case let .syncStateChanged(isSyncing):
                state.isSyncing = isSyncing
                return .none

            case .dismissTapped:
                state.activeError = nil
                state.copiedConfirmationVisible = false
                return .cancel(id: CancelID.copyConfirmation)

            case .copyTapped:
                guard let error = state.activeError else { return .none }
                state.copiedConfirmationVisible = true
                return .run { [pasteboard, clock, message = error.message] send in
                    await pasteboard.setString(message)
                    try await clock.sleep(for: Self.copyConfirmationDuration)
                    await send(.copiedConfirmationTimerEnded)
                }
                .cancellable(id: CancelID.copyConfirmation, cancelInFlight: true)

            case .copiedConfirmationTimerEnded:
                state.copiedConfirmationVisible = false
                return .none
            }
        }
    }
}
