import AppKit
import CryptoKit
import Dependencies
import Foundation

struct OAuthClient: Sendable {
    var authorize: @Sendable () async throws -> TokenResponse
    var refresh: @Sendable (_ refreshToken: String) async throws -> TokenResponse
    var revoke: @Sendable (_ accessToken: String) async throws -> Void
    var handleCallback: @Sendable (URL) -> Void
}

extension OAuthClient: DependencyKey {
    nonisolated static let liveValue: OAuthClient = {
        // Shared callback channel between authorize() and handleCallback()
        let (callbackStream, callbackContinuation) = AsyncStream.makeStream(of: URL.self)

        return OAuthClient(
            authorize: {
                // 1. Generate PKCE verifier + challenge
                var bytes = [UInt8](repeating: 0, count: 32)
                _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                let codeVerifier = Data(bytes).base64URLEncoded()
                let challengeData = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
                let codeChallenge = challengeData.base64URLEncoded()

                // 2. Generate state nonce
                var stateBytes = [UInt8](repeating: 0, count: 16)
                _ = SecRandomCopyBytes(kSecRandomDefault, stateBytes.count, &stateBytes)
                let state = Data(stateBytes).base64URLEncoded()

                // 3. Build authorize URL
                var components = URLComponents(url: LinearConfig.authorizeURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: LinearConfig.clientID),
                    URLQueryItem(name: "redirect_uri", value: LinearConfig.redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: LinearConfig.scopes),
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "code_challenge", value: codeChallenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                ]

                // 4. Open in browser
                await NSWorkspace.shared.open(components.url!)

                // 5. Wait for callback URL
                guard let callbackURL = await callbackStream.first(where: { _ in true }) else {
                    throw OAuthError.invalidCallbackURL
                }

                // 6. Validate state and extract code
                guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state else {
                    throw OAuthError.stateMismatch
                }
                guard let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                    throw OAuthError.missingAuthorizationCode
                }

                // 7. Exchange code for token
                return try await exchangeCode(code, codeVerifier: codeVerifier)
            },
            refresh: { refreshToken in
                var request = URLRequest(url: LinearConfig.tokenURL)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                let body = [
                    "grant_type=refresh_token",
                    "client_id=\(LinearConfig.clientID)",
                    "refresh_token=\(refreshToken)",
                ].joined(separator: "&")
                request.httpBody = body.data(using: .utf8)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw OAuthError.refreshFailed(statusCode)
                }
                return try decodeTokenResponse(data)
            },
            revoke: { accessToken in
                var request = URLRequest(url: LinearConfig.revokeURL)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = "access_token=\(accessToken)".data(using: .utf8)
                _ = try await URLSession.shared.data(for: request)
            },
            handleCallback: { url in
                callbackContinuation.yield(url)
            }
        )
    }()

    nonisolated static let testValue = OAuthClient(
        authorize: unimplemented("OAuthClient.authorize"),
        refresh: unimplemented("OAuthClient.refresh"),
        revoke: unimplemented("OAuthClient.revoke"),
        handleCallback: unimplemented("OAuthClient.handleCallback")
    )
}

// MARK: - Token Exchange

private nonisolated func exchangeCode(_ code: String, codeVerifier: String) async throws -> TokenResponse {
    var request = URLRequest(url: LinearConfig.tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
        "grant_type=authorization_code",
        "client_id=\(LinearConfig.clientID)",
        "redirect_uri=\(LinearConfig.redirectURI)",
        "code=\(code)",
        "code_verifier=\(codeVerifier)",
    ].joined(separator: "&")
    request.httpBody = body.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw OAuthError.tokenExchangeFailed(statusCode)
    }
    return try decodeTokenResponse(data)
}

private nonisolated func decodeTokenResponse(_ data: Data) throws -> TokenResponse {
    struct RawTokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let scope: String
    }
    let raw = try JSONDecoder().decode(RawTokenResponse.self, from: data)
    return TokenResponse(
        accessToken: raw.access_token,
        refreshToken: raw.refresh_token,
        expiresIn: raw.expires_in,
        scope: raw.scope
    )
}

// MARK: - Base64URL

extension Data {
    nonisolated func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension DependencyValues {
    var oauthClient: OAuthClient {
        get { self[OAuthClient.self] }
        set { self[OAuthClient.self] = newValue }
    }
}
