import Foundation

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
}
