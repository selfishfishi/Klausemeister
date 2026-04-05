import Foundation

struct TokenResponse: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String
}

struct LinearUser: Equatable, Sendable {
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
