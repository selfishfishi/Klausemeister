import ComposableArchitecture
import Foundation

@Reducer
struct TeamSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var allTeams: [LinearTeam] = []
        var enabledTeamIds: Set<String> = []
        var teamsToRemove: Set<String> = []
        var loadingStatus: LoadingStatus = .idle
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum LoadingStatus: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct TeamSettingsData: Equatable {
        let apiTeams: [LinearTeam]
        let persistedTeams: [LinearTeamRecord]
    }

    enum Action: Equatable {
        case onAppear
        case teamsLoaded(TaskResult<TeamSettingsData>)
        case enableTeamToggled(teamId: String)
        case removeTeamTapped(teamId: String)
        case saveTapped
        case saveCompleted(TaskResult<[LinearTeam]>)
        case cancelTapped
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        // swiftlint:disable:next nesting
        enum Alert: Equatable {
            case confirmRemoval(teamId: String)
        }

        @CasePathable
        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case teamsUpdated([LinearTeam])
            case dismissed
        }
    }

    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.loadingStatus = .loading
                return .run { [linearAPIClient, databaseClient] send in
                    await send(.teamsLoaded(TaskResult {
                        async let apiTeams = linearAPIClient.fetchTeams()
                        async let persistedTeams = databaseClient.fetchTeams()
                        return try await TeamSettingsData(
                            apiTeams: apiTeams,
                            persistedTeams: persistedTeams
                        )
                    }))
                }

            case let .teamsLoaded(.success(data)):
                state.loadingStatus = .loaded
                let persistedByID = Dictionary(
                    uniqueKeysWithValues: data.persistedTeams.map { ($0.id, $0) }
                )
                // Merge: API teams are the source of truth for available teams,
                // but carry forward colorIndex, isEnabled, isHiddenFromBoard
                // from persisted records. New teams default to disabled.
                state.allTeams = data.apiTeams.map { apiTeam in
                    if let persisted = persistedByID[apiTeam.id] {
                        return LinearTeam(
                            id: apiTeam.id,
                            key: apiTeam.key,
                            name: apiTeam.name,
                            colorIndex: persisted.colorIndex,
                            isEnabled: persisted.isEnabled,
                            isHiddenFromBoard: persisted.isHiddenFromBoard
                        )
                    }
                    var newTeam = apiTeam
                    newTeam.isEnabled = false
                    return newTeam
                }
                state.enabledTeamIds = Set(
                    state.allTeams.filter(\.isEnabled).map(\.id)
                )
                return .none

            case let .teamsLoaded(.failure(error)):
                state.loadingStatus = .failed(error.localizedDescription)
                return .none

            case let .enableTeamToggled(teamId):
                if state.enabledTeamIds.contains(teamId) {
                    state.enabledTeamIds.remove(teamId)
                } else {
                    state.enabledTeamIds.insert(teamId)
                    // If the team was previously marked for removal, cancel that
                    state.teamsToRemove.remove(teamId)
                }
                return .none

            case let .removeTeamTapped(teamId):
                guard let team = state.allTeams.first(where: { $0.id == teamId }) else {
                    return .none
                }
                state.alert = AlertState {
                    TextState("Remove \(team.key)?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmRemoval(teamId: teamId)) {
                        TextState("Remove")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState(
                        "This will delete all imported issues from \(team.name). This cannot be undone."
                    )
                }
                return .none

            case let .alert(.presented(.confirmRemoval(teamId))):
                state.teamsToRemove.insert(teamId)
                state.enabledTeamIds.remove(teamId)
                return .none

            case .alert:
                return .none

            case .saveTapped:
                let teamsToRemove = state.teamsToRemove
                let updatedTeams = state.allTeams.map { team in
                    var team = team
                    team.isEnabled = state.enabledTeamIds.contains(team.id)
                    return team
                }
                // Filter out removed teams from the save list
                let teamsToSave = updatedTeams.filter { !teamsToRemove.contains($0.id) }
                return .run { [databaseClient] send in
                    await send(.saveCompleted(TaskResult {
                        // Delete issues for removed teams (FK cascade handles queue items)
                        for teamId in teamsToRemove {
                            try await databaseClient.deleteIssuesByTeam(teamId)
                            try await databaseClient.deleteTeam(teamId)
                        }
                        // Save the updated team list
                        let records = teamsToSave.map { LinearTeamRecord(from: $0) }
                        try await databaseClient.saveTeams(records)
                        return teamsToSave
                    }))
                }

            case let .saveCompleted(.success(teams)):
                return .send(.delegate(.teamsUpdated(teams)))

            case let .saveCompleted(.failure(error)):
                state.loadingStatus = .failed(
                    "Failed to save: \(error.localizedDescription)"
                )
                return .none

            case .cancelTapped:
                return .send(.delegate(.dismissed))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
