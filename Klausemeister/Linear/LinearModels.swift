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

struct LinearIssue: Equatable, Sendable, Codable {
    let id: String
    let identifier: String
    let title: String
    let status: String
    let statusId: String
    let statusType: String
    let projectName: String?
    let assigneeName: String?
    let priority: Int
    let labels: [String]
    let description: String?
    let url: String
    let createdAt: String
    let updatedAt: String
}

struct LinearWorkflowState: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let position: Double
}
