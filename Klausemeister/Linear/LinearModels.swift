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
    struct Project: Equatable {
        let id: String
        let name: String
    }

    let id: String
    let identifier: String
    let title: String
    let descriptionMarkdown: String?
    let url: URL
    let project: Project?
    let status: InspectorTicketStatus
    let attachedPRs: [AttachedPullRequest]
}

struct InspectorTicketStatus: Equatable {
    enum StatusType: String, Equatable {
        case backlog
        case unstarted
        case started
        case completed
        case canceled
        case triage
        case unknown

        nonisolated init(fromLinear raw: String) {
            self = Self(rawValue: raw.lowercased()) ?? .unknown
        }
    }

    let id: String
    let name: String
    let type: StatusType
}

struct AttachedPullRequest: Equatable, Identifiable {
    enum State: String, Equatable {
        case open
        case closed
        case merged
        case draft
        case unknown
    }

    /// Repo + PR number are all-or-nothing: when the parser extracts them
    /// from either Attachment.metadata or a GitHub URL regex, it always
    /// produces both. Modeling them as one optional prevents callers from
    /// ever seeing `(number != nil, repo == nil)` or vice versa.
    struct GitHubRef: Equatable {
        let owner: String
        let name: String
        let number: Int

        var fullName: String {
            "\(owner)/\(name)"
        }
    }

    let id: String
    let url: URL
    let title: String
    let github: GitHubRef?
    let state: State
}
