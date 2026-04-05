import ComposableArchitecture
import Testing
@testable import Klausemeister

@Test func loginFlowSuccess() async {
    let testToken = TokenResponse(
        accessToken: "lin_oauth_test",
        refreshToken: "refresh_test",
        expiresIn: 86399,
        scope: "read"
    )
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { testToken }
        $0.keychainClient.save = { _, _, _ in }
        $0.linearAPIClient.me = { testUser }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.success) // stores tokens, fires me()
    await store.receive(\.meLoaded.success) {
        $0.status = .authenticated
        $0.user = testUser
    }
}

@Test func loginFlowAuthFailure() async {
    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { throw OAuthError.stateMismatch }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.failure) {
        $0.status = .failed("stateMismatch")
    }
}

@Test func loginFlowMeFailure() async {
    let testToken = TokenResponse(
        accessToken: "lin_oauth_test",
        refreshToken: "refresh_test",
        expiresIn: 86399,
        scope: "read"
    )

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
    await store.receive(\.authCompleted.success) // stores tokens, fires me()
    await store.receive(\.meLoaded.failure) {
        $0.status = .unauthenticated
    }
}

@Test func existingTokenOnAppear() async {
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")
    let tokenData = "existing_token".data(using: .utf8)!

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.load = { _, account in
            if account == LinearConfig.accessTokenAccount { return tokenData }
            return nil
        }
        $0.linearAPIClient.me = { testUser }
    }

    await store.send(.onAppear) {
        $0.status = .authenticating
    }
    await store.receive(\.meLoaded.success) {
        $0.status = .authenticated
        $0.user = testUser
    }
}

@Test func logoutFlow() async {
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")

    let store = TestStore(
        initialState: LinearAuthFeature.State(
            status: .authenticated,
            user: testUser
        )
    ) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.delete = { _, _ in }
    }

    await store.send(.logoutButtonTapped) {
        $0.status = .unauthenticated
        $0.user = nil
    }
}
