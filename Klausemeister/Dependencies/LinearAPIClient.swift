import Dependencies
import Foundation

struct LinearAPIClient {
    // swiftlint:disable:next identifier_name
    var me: @Sendable () async throws -> LinearUser
    var fetchLabeledIssues: @Sendable (_ label: String) async throws -> [LinearIssue]
    var fetchWorkflowStatesByTeam: @Sendable () async throws -> WorkflowStatesByTeam
    var updateIssueStatus: @Sendable (_ issueId: String, _ statusId: String) async throws -> Void
}

// MARK: - Shared GraphQL helper

nonisolated private func graphQLRequest(
    token: String, query: String, variables: [String: Any]?
) async throws -> Data {
    var request = URLRequest(url: LinearConfig.graphqlURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["query": query]
    if let variables { body["variables"] = variables }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw OAuthError.networkError }
    if httpResponse.statusCode == 401 { throw OAuthError.unauthorized }
    if httpResponse.statusCode == 429 { throw LinearAPIError.rateLimited }

    // Detect GraphQL-level errors returned with HTTP 200 + { "errors": [...] }
    if let errorEnvelope = try? JSONDecoder().decode(GraphQLErrorEnvelope.self, from: data),
       !errorEnvelope.errors.isEmpty
    {
        throw LinearAPIError.graphQLErrors(errorEnvelope.errors.map(\.message))
    }

    return data
}

nonisolated private struct GraphQLErrorEnvelope: Decodable {
    struct GraphQLError: Decodable {
        let message: String
    }

    let errors: [GraphQLError]
}

// MARK: - Token loading helper

nonisolated private func loadToken(
    keychainClient: KeychainClient
) async throws -> String {
    guard let tokenData = try await keychainClient.load(
        LinearConfig.keychainService,
        LinearConfig.accessTokenAccount
    ), let token = String(data: tokenData, encoding: .utf8) else {
        throw OAuthError.unauthorized
    }
    return token
}

// MARK: - Live & Test values

extension LinearAPIClient: DependencyKey {
    nonisolated static let liveValue: LinearAPIClient = {
        @Dependency(\.keychainClient) var keychainClient

        return LinearAPIClient(
            me: {
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query { viewer { id name email } }
                """

                let data = try await graphQLRequest(
                    token: token, query: query, variables: nil
                )

                // swiftlint:disable nesting
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
                // swiftlint:enable nesting
                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                return LinearUser(
                    id: graphQLResponse.data.viewer.id,
                    name: graphQLResponse.data.viewer.name,
                    email: graphQLResponse.data.viewer.email
                )
            },

            fetchLabeledIssues: { label in
                let token = try await loadToken(keychainClient: keychainClient)

                // Matches issues that are either:
                //   1. Individually labeled with `label`, OR
                //   2. In a project that is labeled with `label`
                // Deduplicated by id at the merge step in MeisterFeature.performSync.
                let query = """
                query($filter: IssueFilter!, $after: String) {
                  issues(filter: $filter, first: 50, after: $after) {
                    nodes {
                      id identifier title url description updatedAt
                      state { id name type }
                      team { id }
                      project { name }
                      labels { nodes { name } }
                    }
                    pageInfo { hasNextPage endCursor }
                  }
                }
                """

                var allIssues: [LinearIssue] = []
                var seenIds = Set<String>()
                var cursor: String?
                let pageLimit = 20 // 20 × 50 = 1000 max

                for _ in 0 ..< pageLimit {
                    var variables: [String: Any] = [
                        "filter": [
                            "or": [
                                ["labels": ["name": ["eq": label]]],
                                ["project": ["labels": ["name": ["eq": label]]]]
                            ]
                        ]
                    ]
                    if let cursor { variables["after"] = cursor }

                    let data = try await graphQLRequest(
                        token: token, query: query, variables: variables
                    )

                    let page = try JSONDecoder().decode(LabeledIssuesResponse.self, from: data)
                    for node in page.data.issues.nodes {
                        guard seenIds.insert(node.id).inserted else { continue }
                        allIssues.append(node.linearIssue)
                    }

                    guard page.data.issues.pageInfo.hasNextPage,
                          let endCursor = page.data.issues.pageInfo.endCursor
                    else { break }
                    cursor = endCursor
                }

                return allIssues
            },

            fetchWorkflowStatesByTeam: {
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query {
                  teams(first: 250) {
                    nodes {
                      id
                      states { nodes { id name type position } }
                    }
                  }
                }
                """
                let data = try await graphQLRequest(
                    token: token, query: query, variables: nil
                )

                // swiftlint:disable nesting
                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct Teams: Decodable {
                            struct TeamNode: Decodable {
                                struct States: Decodable {
                                    struct StateNode: Decodable {
                                        let id: String
                                        let name: String
                                        let type: String
                                        let position: Double
                                    }

                                    let nodes: [StateNode]
                                }

                                let id: String
                                let states: States
                            }

                            let nodes: [TeamNode]
                        }

                        let teams: Teams
                    }

                    let data: Data
                }
                // swiftlint:enable nesting

                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                var result: WorkflowStatesByTeam = [:]
                for team in graphQLResponse.data.teams.nodes {
                    result[team.id] = team.states.nodes
                        .map { LinearWorkflowState(
                            id: $0.id,
                            name: $0.name,
                            type: $0.type,
                            position: $0.position,
                            teamId: team.id
                        ) }
                        .sorted { $0.position < $1.position }
                }
                return result
            },

            updateIssueStatus: { issueId, statusId in
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                mutation($id: String!, $input: IssueUpdateInput!) {
                  issueUpdate(id: $id, input: $input) { success }
                }
                """
                let variables: [String: Any] = [
                    "id": issueId,
                    "input": ["stateId": statusId]
                ]
                _ = try await graphQLRequest(
                    token: token, query: query, variables: variables
                )
            }
        )
    }()

    nonisolated static let testValue = LinearAPIClient(
        me: unimplemented("LinearAPIClient.me"),
        fetchLabeledIssues: unimplemented("LinearAPIClient.fetchLabeledIssues"),
        fetchWorkflowStatesByTeam: unimplemented("LinearAPIClient.fetchWorkflowStatesByTeam"),
        updateIssueStatus: unimplemented("LinearAPIClient.updateIssueStatus")
    )
}

// MARK: - Labeled Issues Response

// swiftlint:disable nesting
nonisolated private struct LabeledIssuesResponse: Decodable {
    struct Data: Decodable {
        struct Issues: Decodable {
            struct Node: Decodable {
                let id: String
                let identifier: String
                let title: String
                let url: String
                let description: String?
                let updatedAt: String
                struct State: Decodable {
                    let id: String
                    let name: String
                    let type: String
                }

                let state: State
                struct Team: Decodable {
                    let id: String
                }

                let team: Team?
                struct Project: Decodable { let name: String }
                let project: Project?
                struct Labels: Decodable {
                    struct LabelNode: Decodable { let name: String }
                    let nodes: [LabelNode]
                }

                let labels: Labels?

                var linearIssue: LinearIssue {
                    LinearIssue(
                        id: id,
                        identifier: identifier,
                        title: title,
                        status: state.name,
                        statusId: state.id,
                        statusType: state.type,
                        teamId: team?.id ?? "",
                        projectName: project?.name,
                        labels: labels?.nodes.map(\.name) ?? [],
                        description: description,
                        url: url,
                        updatedAt: updatedAt,
                        isOrphaned: false
                    )
                }
            }

            struct PageInfo: Decodable {
                let hasNextPage: Bool
                let endCursor: String?
            }

            let nodes: [Node]
            let pageInfo: PageInfo
        }

        let issues: Issues
    }

    let data: Data
}

// swiftlint:enable nesting

// MARK: - API Errors

enum LinearAPIError: Error, Equatable, LocalizedError {
    case issueNotFound(String)
    case rateLimited
    case graphQLErrors([String])

    var errorDescription: String? {
        switch self {
        case let .issueNotFound(identifier):
            "Issue not found: \(identifier)"
        case .rateLimited:
            "Linear API rate limit exceeded"
        case let .graphQLErrors(messages):
            "Linear API error: \(messages.joined(separator: "; "))"
        }
    }
}

extension DependencyValues {
    var linearAPIClient: LinearAPIClient {
        get { self[LinearAPIClient.self] }
        set { self[LinearAPIClient.self] = newValue }
    }
}
