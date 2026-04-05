import Foundation

enum LinearConfig {
    // MARK: - OAuth
    // Replace with your Linear OAuth app's client ID
    nonisolated static let clientID = "REPLACE_WITH_LINEAR_CLIENT_ID"
    nonisolated static let redirectURI = "klausemeister://oauth/callback"
    nonisolated static let authorizeURL = URL(string: "https://linear.app/oauth/authorize")!
    nonisolated static let tokenURL = URL(string: "https://api.linear.app/oauth/token")!
    nonisolated static let revokeURL = URL(string: "https://api.linear.app/oauth/revoke")!

    // MARK: - API
    nonisolated static let graphqlURL = URL(string: "https://api.linear.app/graphql")!

    // MARK: - Keychain
    nonisolated static let keychainService = "app.klausemeister"
    nonisolated static let accessTokenAccount = "linear_access_token"
    nonisolated static let refreshTokenAccount = "linear_refresh_token"

    // MARK: - Scopes
    nonisolated static let scopes = "read"
}
