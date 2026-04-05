import Dependencies
import Foundation

struct LinearAPIClient: Sendable {
    var me: @Sendable () async throws -> LinearUser
}

extension LinearAPIClient: DependencyKey {
    nonisolated static let liveValue: LinearAPIClient = {
        @Dependency(\.keychainClient) var keychainClient

        return LinearAPIClient(
            me: {
                guard let tokenData = try await keychainClient.load(
                    LinearConfig.keychainService,
                    LinearConfig.accessTokenAccount
                ), let token = String(data: tokenData, encoding: .utf8) else {
                    throw OAuthError.unauthorized
                }

                let query = """
                query { viewer { id name email } }
                """

                var request = URLRequest(url: LinearConfig.graphqlURL)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                struct GraphQLRequest: Encodable {
                    let query: String
                }
                request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query))

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OAuthError.networkError
                }
                if httpResponse.statusCode == 401 {
                    throw OAuthError.unauthorized
                }

                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct Viewer: Decodable {
                            let id: String
                            let name: String
                            let email: String
                        }
                        let viewer: Viewer
                    }
                    let data: Data
                }
                let graphQLResponse = try JSONDecoder().decode(GraphQLResponse.self, from: data)
                return LinearUser(
                    id: graphQLResponse.data.viewer.id,
                    name: graphQLResponse.data.viewer.name,
                    email: graphQLResponse.data.viewer.email
                )
            }
        )
    }()

    nonisolated static let testValue = LinearAPIClient(
        me: unimplemented("LinearAPIClient.me")
    )
}

extension DependencyValues {
    var linearAPIClient: LinearAPIClient {
        get { self[LinearAPIClient.self] }
        set { self[LinearAPIClient.self] = newValue }
    }
}
