import Foundation

enum LinearConfig {
    // MARK: - OAuth
    // Replace with your Linear OAuth app's client ID
    static let clientID = "REPLACE_WITH_LINEAR_CLIENT_ID"
    static let redirectURI = "klausemeister://oauth/callback"
    static let authorizeURL = URL(string: "https://linear.app/oauth/authorize")!
    static let tokenURL = URL(string: "https://api.linear.app/oauth/token")!
    static let revokeURL = URL(string: "https://api.linear.app/oauth/revoke")!

    // MARK: - API
    static let graphqlURL = URL(string: "https://api.linear.app/graphql")!

    // MARK: - Keychain
    static let keychainService = "app.klausemeister"
    static let accessTokenAccount = "linear_access_token"
    static let refreshTokenAccount = "linear_refresh_token"

    // MARK: - Scopes
    static let scopes = "read"
}
