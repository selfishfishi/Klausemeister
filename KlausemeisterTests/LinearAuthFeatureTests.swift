import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

private let testToken = TokenResponse(
    accessToken: "lin_oauth_test",
    refreshToken: "refresh_test",
    expiresIn: 86399,
    scope: "read"
)
private let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")
private let testTeams = [
    LinearTeam(id: "team-1", key: "KLA", name: "Klause", colorIndex: 0, isEnabled: true, isHiddenFromBoard: false)
]

@Test func `login flow success — first auth shows team picker`() async {
    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { testToken }
        $0.keychainClient.save = { _, _, _ in }
        $0.linearAPIClient.me = { testUser }
        $0.databaseClient.fetchTeams = { [] }
        $0.linearAPIClient.fetchTeams = { testTeams }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.success)
    await store.receive(\.meLoaded.success) {
        $0.status = .fetchingTeams
        $0.user = testUser
    }
    await store.receive(\.teamsLoaded.success) {
        $0.status = .teamSelection
        $0.availableTeams = testTeams
        $0.selectedTeamIds = Set(testTeams.map(\.id))
    }
}

@Test func `login flow auth failure`() async {
    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { throw OAuthError.stateMismatch }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.failure) {
        $0.status = .unauthenticated
    }
    await store.receive(\.delegate.errorOccurred)
}

@Test func `login flow me failure`() async {
    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { testToken }
        $0.keychainClient.save = { _, _, _ in }
        $0.keychainClient.delete = { _, _ in }
        $0.linearAPIClient.me = { throw OAuthError.unauthorized }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.success)
    await store.receive(\.meLoaded.failure) {
        $0.status = .unauthenticated
    }
}

@Test func `existing token on appear — teams already persisted`() async {
    let tokenData = Data("existing_token".utf8)
    let teamRecords = testTeams.map { LinearTeamRecord(from: $0) }

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.load = { _, account in
            if account == LinearConfig.accessTokenAccount { return tokenData }
            return nil
        }
        $0.linearAPIClient.me = { testUser }
        $0.databaseClient.fetchTeams = { teamRecords }
    }

    await store.send(.onAppear) {
        $0.status = .authenticating
    }
    await store.receive(\.meLoaded.success) {
        $0.status = .fetchingTeams
        $0.user = testUser
    }
    // Teams already persisted — skip picker, emit teamsConfirmed
    await store.receive(\.delegate.teamsConfirmed)
}

@Test func `logout flow clears teams`() async {
    let store = TestStore(
        initialState: LinearAuthFeature.State(
            status: .authenticated,
            user: testUser
        )
    ) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.delete = { _, _ in }
        $0.databaseClient.deleteAllTeams = {}
    }

    await store.send(.logoutButtonTapped) {
        $0.status = .unauthenticated
        $0.user = nil
    }
}
