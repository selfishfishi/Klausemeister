import ComposableArchitecture
import Foundation

@Reducer
struct LinearAuthFeature {
    @ObservableState
    struct State: Equatable {
        var status: AuthStatus = .unauthenticated
        var user: LinearUser?
        var availableTeams: [LinearTeam] = []
        var selectedTeamIds: Set<String> = []
    }

    enum AuthStatus: Equatable {
        case unauthenticated
        case authenticating
        case fetchingTeams
        case teamSelection
        case authenticated
    }

    enum Action: Equatable {
        case onAppear
        case loginButtonTapped
        case authCompleted(TaskResult<TokenResponse>)
        case meLoaded(TaskResult<LinearUser>)
        case teamsLoaded(TaskResult<[LinearTeam]>)
        case teamToggled(id: String)
        case teamSelectionConfirmed
        case logoutButtonTapped
        case delegate(Delegate)
    }

    @CasePathable
    enum Delegate: Equatable {
        case errorOccurred(message: String)
        case teamsConfirmed([LinearTeam])
    }

    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.keychainClient) var keychainClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.status = .authenticating
                return .run { send in
                    let tokenData = try? await keychainClient.load(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount
                    )
                    guard tokenData != nil else {
                        await send(.meLoaded(.failure(OAuthError.unauthorized)))
                        return
                    }
                    await send(.meLoaded(TaskResult { try await linearAPIClient.me() }))
                }

            case .loginButtonTapped:
                state.status = .authenticating
                return .run { send in
                    await send(.authCompleted(TaskResult { try await oauthClient.authorize() }))
                }
                .cancellable(id: "LinearAuthFeature.authFlow", cancelInFlight: true)

            case let .authCompleted(.success(token)):
                return .run { send in
                    try await keychainClient.save(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount,
                        Data(token.accessToken.utf8)
                    )
                    try await keychainClient.save(
                        LinearConfig.keychainService,
                        LinearConfig.refreshTokenAccount,
                        Data(token.refreshToken.utf8)
                    )
                    await send(.meLoaded(TaskResult { try await linearAPIClient.me() }))
                }

            case let .authCompleted(.failure(error)):
                state.status = .unauthenticated
                return .send(.delegate(.errorOccurred(message: String(describing: error))))

            case let .meLoaded(.success(user)):
                state.user = user
                state.status = .fetchingTeams
                // Check if teams are already persisted (re-launch path)
                return .run { [databaseClient, linearAPIClient] send in
                    let persistedTeams = try await databaseClient.fetchTeams()
                    if !persistedTeams.isEmpty {
                        // Teams already configured — skip picker
                        let teams = persistedTeams.map { LinearTeam(from: $0) }
                        await send(.delegate(.teamsConfirmed(teams)))
                    } else {
                        // First auth — fetch teams from Linear
                        await send(.teamsLoaded(TaskResult {
                            try await linearAPIClient.fetchTeams()
                        }))
                    }
                }

            case .meLoaded(.failure):
                state.status = .unauthenticated
                state.user = nil
                return .run { [keychainClient] _ in
                    await clearStoredTokens(keychainClient)
                }

            case let .teamsLoaded(.success(teams)):
                state.status = .teamSelection
                state.availableTeams = teams
                state.selectedTeamIds = Set(teams.map(\.id))
                return .none

            case let .teamsLoaded(.failure(error)):
                // If fetching teams fails, still allow auth to complete
                // (user can configure teams later from settings)
                state.status = .authenticated
                return .send(.delegate(.errorOccurred(
                    message: "Failed to load teams: \(error.localizedDescription)"
                )))

            case let .teamToggled(id):
                if state.selectedTeamIds.contains(id) {
                    state.selectedTeamIds.remove(id)
                } else {
                    state.selectedTeamIds.insert(id)
                }
                return .none

            case .teamSelectionConfirmed:
                guard !state.selectedTeamIds.isEmpty else { return .none }
                let confirmedTeams = state.availableTeams
                    .filter { state.selectedTeamIds.contains($0.id) }
                    .map { team in
                        var team = team
                        team.isEnabled = true
                        return team
                    }
                return .run { [databaseClient] send in
                    do {
                        let records = confirmedTeams.map { LinearTeamRecord(from: $0) }
                        try await databaseClient.saveTeams(records)
                        await send(.delegate(.teamsConfirmed(confirmedTeams)))
                    } catch {
                        await send(.delegate(.errorOccurred(
                            message: "Failed to save team selection: \(error.localizedDescription)"
                        )))
                    }
                }

            case .logoutButtonTapped:
                state.status = .unauthenticated
                state.user = nil
                state.availableTeams = []
                state.selectedTeamIds = []
                return .run { [keychainClient, databaseClient] _ in
                    await clearStoredTokens(keychainClient)
                    try? await databaseClient.deleteAllTeams()
                }

            case .delegate:
                return .none
            }
        }
    }
}

private func clearStoredTokens(_ keychainClient: KeychainClient) async {
    try? await keychainClient.delete(LinearConfig.keychainService, LinearConfig.accessTokenAccount)
    try? await keychainClient.delete(LinearConfig.keychainService, LinearConfig.refreshTokenAccount)
}

// MARK: - Record Conversions

extension LinearTeam {
    nonisolated init(from record: LinearTeamRecord) {
        self.init(
            id: record.id,
            key: record.key,
            name: record.name,
            colorIndex: record.colorIndex,
            isEnabled: record.isEnabled,
            isHiddenFromBoard: record.isHiddenFromBoard,
            ingestAllIssues: record.ingestAllIssues,
            filterLabel: record.filterLabel
        )
    }
}

extension LinearTeamRecord {
    nonisolated init(from team: LinearTeam) {
        self.init(
            id: team.id,
            key: team.key,
            name: team.name,
            colorIndex: team.colorIndex,
            isEnabled: team.isEnabled,
            isHiddenFromBoard: team.isHiddenFromBoard,
            ingestAllIssues: team.ingestAllIssues,
            filterLabel: team.filterLabel
        )
    }
}
