import Dependencies
import Foundation

struct LinearAPIClient: Sendable {
    var me: @Sendable () async throws -> LinearUser
    var fetchIssue: @Sendable (_ identifier: String) async throws -> LinearIssue
    var fetchIssues: @Sendable (_ identifiers: [String]) async throws -> [LinearIssue]
    var updateIssueStatus: @Sendable (_ issueId: String, _ statusId: String) async throws -> Void
    var fetchWorkflowStates: @Sendable () async throws -> [LinearWorkflowState]
}

// MARK: - Shared GraphQL helper

private nonisolated func graphQLRequest(
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
    return data
}

// MARK: - Token loading helper

private nonisolated func loadToken(
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
                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                return LinearUser(
                    id: graphQLResponse.data.viewer.id,
                    name: graphQLResponse.data.viewer.name,
                    email: graphQLResponse.data.viewer.email
                )
            },

            fetchIssue: { identifier in
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query($filter: IssueFilter!) {
                  issues(filter: $filter, first: 1) {
                    nodes {
                      id identifier title url description priority createdAt updatedAt
                      state { id name type position }
                      project { name }
                      assignee { name }
                      labels { nodes { name } }
                    }
                  }
                }
                """
                let variables: [String: Any] = [
                    "filter": ["identifier": ["eq": identifier]]
                ]
                let data = try await graphQLRequest(
                    token: token, query: query, variables: variables
                )

                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct Issues: Decodable {
                            struct Node: Decodable {
                                let id: String
                                let identifier: String
                                let title: String
                                let url: String
                                let description: String?
                                let priority: Int
                                let createdAt: String
                                let updatedAt: String
                                struct State: Decodable {
                                    let id: String
                                    let name: String
                                    let type: String
                                    let position: Double
                                }
                                let state: State
                                struct Project: Decodable { let name: String }
                                let project: Project?
                                struct Assignee: Decodable { let name: String }
                                let assignee: Assignee?
                                struct Labels: Decodable {
                                    struct LabelNode: Decodable { let name: String }
                                    let nodes: [LabelNode]
                                }
                                let labels: Labels
                            }
                            let nodes: [Node]
                        }
                        let issues: Issues
                    }
                    let data: Data
                }

                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                guard let node = graphQLResponse.data.issues.nodes.first else {
                    throw LinearAPIError.issueNotFound(identifier)
                }
                return LinearIssue(
                    id: node.id,
                    identifier: node.identifier,
                    title: node.title,
                    status: node.state.name,
                    statusId: node.state.id,
                    statusType: node.state.type,
                    projectName: node.project?.name,
                    assigneeName: node.assignee?.name,
                    priority: node.priority,
                    labels: node.labels.nodes.map(\.name),
                    description: node.description,
                    url: node.url,
                    createdAt: node.createdAt,
                    updatedAt: node.updatedAt
                )
            },

            fetchIssues: { identifiers in
                guard !identifiers.isEmpty else { return [] }
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query($filter: IssueFilter!) {
                  issues(filter: $filter, first: \(identifiers.count)) {
                    nodes {
                      id identifier title url description priority createdAt updatedAt
                      state { id name type position }
                      project { name }
                      assignee { name }
                      labels { nodes { name } }
                    }
                  }
                }
                """
                let variables: [String: Any] = [
                    "filter": ["identifier": ["in": identifiers]]
                ]
                let data = try await graphQLRequest(
                    token: token, query: query, variables: variables
                )

                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct Issues: Decodable {
                            struct Node: Decodable {
                                let id: String
                                let identifier: String
                                let title: String
                                let url: String
                                let description: String?
                                let priority: Int
                                let createdAt: String
                                let updatedAt: String
                                struct State: Decodable {
                                    let id: String; let name: String; let type: String; let position: Double
                                }
                                let state: State
                                struct Project: Decodable { let name: String }
                                let project: Project?
                                struct Assignee: Decodable { let name: String }
                                let assignee: Assignee?
                                struct Labels: Decodable {
                                    struct LabelNode: Decodable { let name: String }
                                    let nodes: [LabelNode]
                                }
                                let labels: Labels
                            }
                            let nodes: [Node]
                        }
                        let issues: Issues
                    }
                    let data: Data
                }

                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                return graphQLResponse.data.issues.nodes.map { node in
                    LinearIssue(
                        id: node.id,
                        identifier: node.identifier,
                        title: node.title,
                        status: node.state.name,
                        statusId: node.state.id,
                        statusType: node.state.type,
                        projectName: node.project?.name,
                        assigneeName: node.assignee?.name,
                        priority: node.priority,
                        labels: node.labels.nodes.map(\.name),
                        description: node.description,
                        url: node.url,
                        createdAt: node.createdAt,
                        updatedAt: node.updatedAt
                    )
                }
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
                    "input": ["stateId": statusId],
                ]
                _ = try await graphQLRequest(
                    token: token, query: query, variables: variables
                )
            },

            fetchWorkflowStates: {
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query {
                  organization {
                    teams(first: 1) {
                      nodes {
                        states { nodes { id name type position } }
                      }
                    }
                  }
                }
                """
                let data = try await graphQLRequest(
                    token: token, query: query, variables: nil
                )

                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct Organization: Decodable {
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
                                    let states: States
                                }
                                let nodes: [TeamNode]
                            }
                            let teams: Teams
                        }
                        let organization: Organization
                    }
                    let data: Data
                }

                let graphQLResponse = try JSONDecoder().decode(
                    GraphQLResponse.self, from: data
                )
                guard let team = graphQLResponse.data.organization.teams.nodes.first else {
                    return []
                }
                return team.states.nodes
                    .map { LinearWorkflowState(
                        id: $0.id, name: $0.name, type: $0.type, position: $0.position
                    ) }
                    .sorted { $0.position < $1.position }
            }
        )
    }()

    nonisolated static let testValue = LinearAPIClient(
        me: unimplemented("LinearAPIClient.me"),
        fetchIssue: unimplemented("LinearAPIClient.fetchIssue"),
        fetchIssues: unimplemented("LinearAPIClient.fetchIssues"),
        updateIssueStatus: unimplemented("LinearAPIClient.updateIssueStatus"),
        fetchWorkflowStates: unimplemented("LinearAPIClient.fetchWorkflowStates")
    )
}

// MARK: - API Errors

enum LinearAPIError: Error, Equatable {
    case issueNotFound(String)
}

extension DependencyValues {
    var linearAPIClient: LinearAPIClient {
        get { self[LinearAPIClient.self] }
        set { self[LinearAPIClient.self] = newValue }
    }
}
