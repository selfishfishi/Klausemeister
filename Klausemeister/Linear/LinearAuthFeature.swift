import ComposableArchitecture
import Foundation

@Reducer
struct LinearAuthFeature {
    @ObservableState
    struct State: Equatable {
        var status: AuthStatus = .unauthenticated
        var user: LinearUser?
    }

    enum AuthStatus: Equatable {
        case unauthenticated
        case authenticating
        case authenticated
    }

    enum Action: Equatable {
        case onAppear
        case loginButtonTapped
        case authCompleted(TaskResult<TokenResponse>)
        case meLoaded(TaskResult<LinearUser>)
        case logoutButtonTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case errorOccurred(message: String)
    }

    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.keychainClient) var keychainClient

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
                state.status = .authenticated
                state.user = user
                return .none

            case .meLoaded(.failure):
                state.status = .unauthenticated
                state.user = nil
                return .run { [keychainClient] _ in
                    await clearStoredTokens(keychainClient)
                }

            case .logoutButtonTapped:
                state.status = .unauthenticated
                state.user = nil
                return .run { [keychainClient] _ in
                    await clearStoredTokens(keychainClient)
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
