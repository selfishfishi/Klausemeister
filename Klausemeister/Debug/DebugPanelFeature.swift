import ComposableArchitecture
import Foundation

@Reducer
struct DebugPanelFeature {
    @ObservableState
    struct State: Equatable {
        var showPanel = false
        var events: [DebugEvent] = []
        var shimStates: [ShimStateInfo] = []
        var shimSymlinkTarget: String = ""
        var socketExists = false
    }

    struct DebugEvent: Equatable, Identifiable {
        let id: UUID
        let timestamp: Date
        let description: String
    }

    private static let maxEvents = 50

    enum Action: Equatable {
        case panelToggled
        case refreshTapped
        case refreshCompleted(ShimDiagnosticsResult)
        case eventReceived(MCPServerEvent)
    }

    @Dependency(\.mcpServerClient) var mcpServerClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .panelToggled:
                state.showPanel.toggle()
                if state.showPanel {
                    return .send(.refreshTapped)
                }
                return .none

            case .refreshTapped:
                return .run { [mcpServerClient] send in
                    let result = await mcpServerClient.scanShimDiagnostics()
                    await send(.refreshCompleted(result))
                }

            case let .refreshCompleted(result):
                state.shimStates = result.shimStates
                state.shimSymlinkTarget = result.shimSymlinkTarget
                state.socketExists = result.socketExists
                return .none

            case let .eventReceived(event):
                let entry = DebugEvent(
                    id: uuid(),
                    timestamp: date.now,
                    description: Self.describe(event)
                )
                state.events.insert(entry, at: 0)
                if state.events.count > Self.maxEvents {
                    state.events.removeLast(state.events.count - Self.maxEvents)
                }
                return .none
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func describe(_ event: MCPServerEvent) -> String {
        switch event {
        case let .errorOccurred(message):
            "Error: \(message)"
        case let .progressReported(worktreeId, _, statusText):
            "Progress [\(worktreeId.prefix(8))]: \(statusText)"
        case let .activityReported(worktreeId, text):
            "Activity [\(worktreeId.prefix(8))]: \(text)"
        case let .meisterHelloReceived(worktreeId):
            "Hello received [\(worktreeId.prefix(8))]"
        case let .meisterConnectionClosed(worktreeId):
            "Connection closed [\(worktreeId.prefix(8))]"
        case let .itemMovedToProcessing(worktreeId, issueLinearId):
            "Item → processing [\(worktreeId.prefix(8))]: \(issueLinearId)"
        case let .itemMovedToOutbox(worktreeId, issueLinearId):
            "Item → outbox [\(worktreeId.prefix(8))]: \(issueLinearId)"
        case let .itemAddedToInbox(worktreeId, issueLinearId):
            "Item → inbox [\(worktreeId.prefix(8))]: \(issueLinearId)"
        case let .itemRemovedFromInbox(worktreeId, issueLinearId):
            "Item ← inbox [\(worktreeId.prefix(8))]: \(issueLinearId)"
        case let .scheduleSaved(scheduleId):
            "Schedule saved [\(scheduleId.prefix(8))]"
        case let .scheduleDeleted(scheduleId):
            "Schedule deleted [\(scheduleId.prefix(8))]"
        case let .scheduleItemStatusChanged(scheduleItemId, status):
            "Schedule item → \(status) [\(scheduleItemId.prefix(8))]"
        case let .scheduleRun(scheduleId):
            "Schedule run [\(scheduleId.prefix(8))]"
        }
    }
}
