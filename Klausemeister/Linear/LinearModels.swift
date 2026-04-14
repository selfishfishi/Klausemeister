import Foundation

extension ISO8601DateFormatter {
    /// Shared cached instance — avoids repeated construction in hot paths.
    /// Thread-safe for `string(from:)` and `date(from:)` calls.
    nonisolated static let shared = ISO8601DateFormatter()
}

struct TokenResponse: Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String
}

struct LinearUser: Equatable {
    let id: String
    let name: String
    let email: String
}

enum OAuthError: Error, Equatable {
    case invalidCallbackURL
    case stateMismatch
    case missingAuthorizationCode
    case tokenExchangeFailed(Int)
    case refreshFailed(Int)
    case unauthorized
    case networkError
}

struct LinearIssue: Equatable, Codable {
    /// Canonical name used for issues with no Linear project in filter lookups.
    nonisolated static let noProjectName = ""

    let id: String
    let identifier: String
    let title: String
    let status: String
    let statusId: String
    let statusType: String
    let teamId: String
    let projectName: String?
    let labels: [String]
    let description: String?
    let url: String
    let updatedAt: String
    var isOrphaned: Bool = false
}

struct LinearWorkflowState: Equatable, Identifiable {
    let id: String
    let name: String
    let type: String
    let position: Double
    let teamId: String
}

typealias WorkflowStatesByTeam = [String: [LinearWorkflowState]]

struct LinearTeam: Equatable, Identifiable, Codable {
    let id: String
    let key: String
    let name: String
    var colorIndex: Int
    var isEnabled: Bool
    var isHiddenFromBoard: Bool
    var ingestAllIssues: Bool = false
    var filterLabel: String = "klause"
}

// MARK: - Inspector ticket detail

struct InspectorTicketDetail: Equatable {
    let id: String
    let identifier: String
    let title: String
    let descriptionMarkdown: String?
    let url: String
    let projectName: String?
    let projectId: String?
    let status: InspectorTicketStatus
    let attachedPRs: [AttachedPullRequest]
}

struct InspectorTicketStatus: Equatable {
    let id: String
    let name: String
    let type: String
}

struct AttachedPullRequest: Equatable, Identifiable {
    enum State: String, Equatable {
        case open
        case closed
        case merged
        case draft
        case unknown
    }

    let id: String
    let url: String
    let title: String
    let number: Int?
    let repo: String?
    let state: State
}
