import ComposableArchitecture
import Foundation

@Reducer
struct StateMappingFeature {
    @ObservableState
    struct State: Equatable {
        var teams: [LinearTeam]
        var workflowStatesByTeam: WorkflowStatesByTeam
        var mappings: StateMappingTable
        var selectedTeamId: String?

        /// Snapshot of mappings at construction for dirty-checking.
        var originalMappings: StateMappingTable
        var saveError: String?

        init(
            teams: [LinearTeam],
            workflowStatesByTeam: WorkflowStatesByTeam,
            mappings: StateMappingTable
        ) {
            self.teams = teams
            self.workflowStatesByTeam = workflowStatesByTeam
            self.mappings = mappings
            selectedTeamId = teams.first?.id
            originalMappings = mappings
        }
    }

    enum Action: Equatable {
        case onAppear
        case teamSelected(String)
        case mappingChanged(teamId: String, linearStateId: String, meisterState: MeisterState)
        case saveTapped
        case saveCompleted(TaskResult<StateMappingTable>)
        case cancelTapped
        case delegate(Delegate)

        @CasePathable
        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case mappingsSaved(StateMappingTable)
            case dismissed
        }
    }

    @Dependency(\.stateMappingClient) var stateMappingClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none

            case let .teamSelected(teamId):
                state.selectedTeamId = teamId
                return .none

            case let .mappingChanged(teamId, linearStateId, meisterState):
                state.mappings[teamId, default: [:]][linearStateId] = meisterState
                return .none

            case .saveTapped:
                state.saveError = nil
                let mappings = state.mappings
                let workflowStates = state.workflowStatesByTeam
                return .run { [stateMappingClient] send in
                    await send(.saveCompleted(TaskResult {
                        try await stateMappingClient.saveMappingTable(mappings, workflowStates)
                        return mappings
                    }))
                }

            case let .saveCompleted(.success(table)):
                return .send(.delegate(.mappingsSaved(table)))

            case let .saveCompleted(.failure(error)):
                state.saveError = error.localizedDescription
                return .none

            case .cancelTapped:
                return .send(.delegate(.dismissed))

            case .delegate:
                return .none
            }
        }
    }
}
