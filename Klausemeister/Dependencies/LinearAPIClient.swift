// swiftlint:disable file_length
import Dependencies
import Foundation
import OSLog

/// GraphQL boundary for Linear. All closures expect the access token to
/// be available in `KeychainClient` under `LinearConfig.keychainService`
/// / `LinearConfig.accessTokenAccount` — missing tokens throw
/// `OAuthError.unauthorized`, which callers should treat as "user needs
/// to reconnect".
///
/// Pagination and rate-limit handling:
///
/// - Issue fetches (`fetchLabeledIssues`, `fetchAllTeamIssues`) paginate
///   internally with a hard cap of 20 × 50 = 1,000 rows per call to
///   avoid unbounded walks and Linear's complexity-score limits.
/// - HTTP 429 surfaces as `LinearAPIError.rateLimited`; a 401 surfaces
///   as `OAuthError.unauthorized`. GraphQL-level `errors[]` arrays on an
///   HTTP 200 surface as `LinearAPIError.graphQLErrors`.
///
/// JSON decoding happens off the cooperative thread pool via
/// `Task.detached(priority: .userInitiated)` — Linear's payloads can be
/// large on first sync and decoding on the main pool would stall the UI.
struct LinearAPIClient {
    // swiftlint:disable:next identifier_name
    var me: @Sendable () async throws -> LinearUser
    var fetchLabeledIssues: @Sendable (_ label: String, _ teamId: String?) async throws -> [LinearIssue]
    var fetchAllTeamIssues: @Sendable (_ teamId: String) async throws -> [LinearIssue]
    var fetchTeams: @Sendable () async throws -> [LinearTeam]
    var fetchLabels: @Sendable () async throws -> [String]
    var fetchWorkflowStatesByTeam: @Sendable () async throws -> WorkflowStatesByTeam
    var updateIssueStatus: @Sendable (_ issueId: String, _ statusId: String) async throws -> Void
    var fetchTicketDetail: @Sendable (_ id: String) async throws -> InspectorTicketDetail
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
    if let errorEnvelope = try? await decodeOffMain(GraphQLErrorEnvelope.self, from: data),
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

/// Decodes JSON on a background thread to avoid blocking the cooperative pool.
nonisolated private func decodeOffMain<T: Decodable & Sendable>(
    _: T.Type, from data: Data
) async throws -> T {
    try await Task.detached(priority: .userInitiated) {
        try JSONDecoder().decode(T.self, from: data)
    }.value
}

// MARK: - Paginated issue fetch helper

/// Runs a paginated issues query with a single filter (no OR), appending
/// results to `allIssues` and deduplicating via `seenIds`.
nonisolated private func fetchPaginatedIssues(
    token: String,
    query: String,
    filter: [String: Any],
    into allIssues: inout [LinearIssue],
    seenIds: inout Set<String>
) async throws {
    var cursor: String?
    let pageLimit = 20 // 20 × 50 = 1000 max per filter

    for _ in 0 ..< pageLimit {
        var variables: [String: Any] = ["filter": filter]
        if let cursor { variables["after"] = cursor }

        let data = try await graphQLRequest(
            token: token, query: query, variables: variables
        )

        let page = try await decodeOffMain(LabeledIssuesResponse.self, from: data)
        for node in page.data.issues.nodes {
            guard seenIds.insert(node.id).inserted else { continue }
            allIssues.append(node.linearIssue)
        }

        guard page.data.issues.pageInfo.hasNextPage,
              let endCursor = page.data.issues.pageInfo.endCursor
        else { break }
        cursor = endCursor
    }
}

// MARK: - Shared issue fields

nonisolated private let issueFields = """
      id identifier title url description updatedAt
      state { id name type }
      team { id }
      project { name }
      labels { nodes { name } }
"""

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
                let graphQLResponse = try await decodeOffMain(
                    GraphQLResponse.self, from: data
                )
                return LinearUser(
                    id: graphQLResponse.data.viewer.id,
                    name: graphQLResponse.data.viewer.name,
                    email: graphQLResponse.data.viewer.email
                )
            },

            fetchLabeledIssues: { label, teamId in
                let token = try await loadToken(keychainClient: keychainClient)

                // Two separate, simple queries instead of one complex OR filter.
                // Linear's complexity scoring punishes nested OR filters with
                // sub-relation traversals (project→labels) heavily — splitting
                // avoids the "Query too complex" error that the combined query
                // triggers on larger workspaces.

                // Query 1: issues directly labeled with `label`
                let directQuery = """
                query($filter: IssueFilter!, $after: String) {
                  issues(filter: $filter, first: 50, after: $after) {
                    nodes { \(issueFields) }
                    pageInfo { hasNextPage endCursor }
                  }
                }
                """

                // Query 2: issues in projects labeled with `label`
                let projectQuery = directQuery // same shape, different filter

                var allIssues: [LinearIssue] = []
                var seenIds = Set<String>()

                let excludeCanceled: [String: Any] = ["type": ["neq": "canceled"]]
                let teamFilter: [String: Any]? = teamId.map { ["id": ["eq": $0]] }

                var directFilter: [String: Any] = [
                    "labels": ["name": ["eq": label]],
                    "state": excludeCanceled
                ]
                if let teamFilter { directFilter["team"] = teamFilter }

                // Fetch issues with the direct label
                try await fetchPaginatedIssues(
                    token: token,
                    query: directQuery,
                    filter: directFilter,
                    into: &allIssues,
                    seenIds: &seenIds
                )

                var projectFilter: [String: Any] = [
                    "project": ["labels": ["name": ["eq": label]]],
                    "state": excludeCanceled
                ]
                if let teamFilter { projectFilter["team"] = teamFilter }

                // Fetch issues from labeled projects
                try await fetchPaginatedIssues(
                    token: token,
                    query: projectQuery,
                    filter: projectFilter,
                    into: &allIssues,
                    seenIds: &seenIds
                )

                return allIssues
            },

            fetchAllTeamIssues: { teamId in
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query($filter: IssueFilter!, $after: String) {
                  issues(filter: $filter, first: 50, after: $after) {
                    nodes { \(issueFields) }
                    pageInfo { hasNextPage endCursor }
                  }
                }
                """

                var allIssues: [LinearIssue] = []
                var seenIds = Set<String>()

                let filter: [String: Any] = [
                    "team": ["id": ["eq": teamId]],
                    "state": ["type": ["neq": "canceled"]]
                ]

                try await fetchPaginatedIssues(
                    token: token,
                    query: query,
                    filter: filter,
                    into: &allIssues,
                    seenIds: &seenIds
                )

                return allIssues
            },

            fetchTeams: {
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query {
                  teams(first: 50) {
                    nodes { id key name }
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
                                let id: String
                                let key: String
                                let name: String
                            }

                            let nodes: [TeamNode]
                        }

                        let teams: Teams
                    }

                    let data: Data
                }
                // swiftlint:enable nesting

                let graphQLResponse = try await decodeOffMain(
                    GraphQLResponse.self, from: data
                )
                return graphQLResponse.data.teams.nodes.enumerated().map { index, node in
                    LinearTeam(
                        id: node.id,
                        key: node.key,
                        name: node.name,
                        colorIndex: index % 6,
                        isEnabled: true,
                        isHiddenFromBoard: false
                    )
                }
            },

            fetchLabels: {
                let token = try await loadToken(keychainClient: keychainClient)

                // Linear allows up to 250 per page; no pagination for labels
                let query = """
                query {
                  issueLabels(first: 250) {
                    nodes { name }
                  }
                }
                """
                let data = try await graphQLRequest(
                    token: token, query: query, variables: nil
                )

                // swiftlint:disable nesting
                struct GraphQLResponse: Decodable {
                    struct Data: Decodable {
                        struct IssueLabels: Decodable {
                            struct LabelNode: Decodable { let name: String }
                            let nodes: [LabelNode]
                        }

                        let issueLabels: IssueLabels
                    }

                    let data: Data
                }
                // swiftlint:enable nesting

                let graphQLResponse = try await decodeOffMain(
                    GraphQLResponse.self, from: data
                )
                return graphQLResponse.data.issueLabels.nodes.map(\.name)
            },

            fetchWorkflowStatesByTeam: {
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query {
                  teams(first: 50) {
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

                let graphQLResponse = try await decodeOffMain(
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
            },

            fetchTicketDetail: { id in
                let token = try await loadToken(keychainClient: keychainClient)

                let query = """
                query($id: String!) {
                  issue(id: $id) {
                    id identifier title url description
                    state { id name type }
                    project { id name }
                    attachments(first: 25) {
                      nodes { id url title sourceType metadata }
                    }
                  }
                }
                """
                let data = try await graphQLRequest(
                    token: token, query: query, variables: ["id": id]
                )
                return try await decodeTicketDetail(from: data, requestedId: id)
            }
        )
    }()

    nonisolated static let testValue = LinearAPIClient(
        me: unimplemented("LinearAPIClient.me"),
        fetchLabeledIssues: unimplemented("LinearAPIClient.fetchLabeledIssues"),
        fetchAllTeamIssues: unimplemented("LinearAPIClient.fetchAllTeamIssues"),
        fetchTeams: unimplemented("LinearAPIClient.fetchTeams"),
        fetchLabels: unimplemented("LinearAPIClient.fetchLabels"),
        fetchWorkflowStatesByTeam: unimplemented("LinearAPIClient.fetchWorkflowStatesByTeam"),
        updateIssueStatus: unimplemented("LinearAPIClient.updateIssueStatus"),
        fetchTicketDetail: unimplemented("LinearAPIClient.fetchTicketDetail")
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

// MARK: - Ticket detail decoding

// swiftlint:disable nesting
nonisolated struct TicketDetailResponse: Decodable {
    struct DataEnvelope: Decodable {
        struct Issue: Decodable {
            let id: String
            let identifier: String
            let title: String
            let url: String
            let description: String?
            struct State: Decodable {
                let id: String
                let name: String
                let type: String
            }

            let state: State
            struct Project: Decodable {
                let id: String
                let name: String
            }

            let project: Project?
            struct Attachments: Decodable {
                struct Node: Decodable {
                    let id: String
                    let url: String
                    let title: String
                    let sourceType: String?
                    /// metadata is a JSON object — decode as raw Data and parse
                    let metadata: JSONValue?
                }

                let nodes: [Node]
            }

            let attachments: Attachments?
        }

        let issue: Issue?
    }

    let data: DataEnvelope
}

// swiftlint:enable nesting

/// Minimal JSON value for decoding Linear's `Attachment.metadata` (free-form object).
nonisolated enum JSONValue: Decodable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value"
            )
        )
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value): value
        case let .double(value): Int(value)
        case let .string(value): Int(value)
        default: nil
        }
    }

    func object(_ key: String) -> JSONValue? {
        if case let .object(dict) = self { return dict[key] }
        return nil
    }
}

nonisolated private let ticketDetailLog = Logger(
    subsystem: "com.klausemeister", category: "LinearAPI"
)

nonisolated private let pullRequestURLRegex: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)"#
)

/// Decodes a GraphQL ticket-detail response and maps to `InspectorTicketDetail`.
nonisolated func decodeTicketDetail(
    from data: Data, requestedId: String
) async throws -> InspectorTicketDetail {
    let envelope = try await decodeOffMain(TicketDetailResponse.self, from: data)
    guard let issue = envelope.data.issue else {
        throw LinearAPIError.issueNotFound(requestedId)
    }
    guard let issueURL = URL(string: issue.url) else {
        throw LinearAPIError.graphQLErrors(["Issue URL is malformed: \(issue.url)"])
    }
    let attached = (issue.attachments?.nodes ?? [])
        .filter { ($0.sourceType ?? "").lowercased() == "github" }
        .compactMap(mapPullRequestAttachment)
    let project = issue.project.map {
        InspectorTicketDetail.Project(id: $0.id, name: $0.name)
    }
    return InspectorTicketDetail(
        id: issue.id,
        identifier: issue.identifier,
        title: issue.title,
        descriptionMarkdown: issue.description,
        url: issueURL,
        project: project,
        status: InspectorTicketStatus(
            id: issue.state.id,
            name: issue.state.name,
            type: .init(fromLinear: issue.state.type)
        ),
        attachedPRs: attached
    )
}

nonisolated private func mapPullRequestAttachment(
    _ node: TicketDetailResponse.DataEnvelope.Issue.Attachments.Node
) -> AttachedPullRequest? {
    guard let url = URL(string: node.url) else {
        ticketDetailLog.warning(
            "PR attachment URL malformed; dropping attachment. url=\(node.url, privacy: .public)"
        )
        return nil
    }
    let metadata = node.metadata
    return AttachedPullRequest(
        id: node.id,
        url: url,
        title: node.title,
        github: parseGitHubRef(metadata: metadata, url: node.url),
        state: parsePRState(metadata: metadata, url: node.url)
    )
}

nonisolated private func parsePRState(
    metadata: JSONValue?, url: String
) -> AttachedPullRequest.State {
    let raw = metadata?.object("status")?.stringValue
        ?? metadata?.object("state")?.stringValue
    guard let raw else {
        ticketDetailLog.warning("PR attachment missing state; url=\(url, privacy: .public)")
        return .unknown
    }
    if let state = AttachedPullRequest.State(rawValue: raw.lowercased()) {
        return state
    }
    ticketDetailLog.warning(
        "Unrecognized PR state '\(raw, privacy: .public)' from Linear; url=\(url, privacy: .public)"
    )
    return .unknown
}

/// Prefers Attachment.metadata values when both repo and number are present;
/// falls back to parsing the URL (`https://github.com/<owner>/<repo>/pull/<n>`).
/// Returns nil when neither source yields a complete ref.
nonisolated private func parseGitHubRef(
    metadata: JSONValue?, url: String
) -> AttachedPullRequest.GitHubRef? {
    if let fromMetadata = refFromMetadata(metadata) {
        return fromMetadata
    }
    return refFromURL(url)
}

nonisolated private func refFromMetadata(_ metadata: JSONValue?) -> AttachedPullRequest.GitHubRef? {
    guard let metadata,
          let combined = metadata.object("repo")?.stringValue
          ?? metadata.object("repository")?.stringValue,
          let number = metadata.object("number")?.intValue
    else { return nil }
    let parts = combined.split(separator: "/", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    return .init(owner: parts[0], name: parts[1], number: number)
}

nonisolated private func refFromURL(_ url: String) -> AttachedPullRequest.GitHubRef? {
    guard let regex = pullRequestURLRegex else { return nil }
    let range = NSRange(url.startIndex ..< url.endIndex, in: url)
    guard let match = regex.firstMatch(in: url, range: range),
          match.numberOfRanges == 4,
          let ownerRange = Range(match.range(at: 1), in: url),
          let repoRange = Range(match.range(at: 2), in: url),
          let numberRange = Range(match.range(at: 3), in: url),
          let number = Int(url[numberRange])
    else { return nil }
    return .init(
        owner: String(url[ownerRange]),
        name: String(url[repoRange]),
        number: number
    )
}

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
