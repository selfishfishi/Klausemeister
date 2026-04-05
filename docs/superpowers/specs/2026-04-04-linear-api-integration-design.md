# KLA-15: Linear API Integration — Design Spec

## Goal

Integrate with the Linear API so Klausemeister can authenticate and read Linear data. MVP scope: working OAuth + a verified `me` query. No UI.

## Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Auth mechanism | OAuth 2.0 with PKCE | Native app — no embedded client secret |
| GraphQL client | swift-graphql (maticzav) | Type-safe DSL, URLSession transport, lighter than Apollo |
| Keychain wrapper | Security.framework direct | No third-party deps, three operations needed |
| Architecture | TCA dependencies + reducer | Matches existing codebase patterns |
| Codegen strategy | CLI against committed schema snapshot | Manual run when schema changes, not a build phase |

## OAuth 2.0 with PKCE

### Flow

1. Generate `code_verifier` (random 64-byte, base64url) and `code_challenge` (SHA256 of verifier)
2. Generate `state` nonce for CSRF protection
3. Open `https://linear.app/oauth/authorize` in default browser with params:
   - `client_id`, `redirect_uri=klausemeister://oauth/callback`
   - `response_type=code`, `scope=read`
   - `state`, `code_challenge`, `code_challenge_method=S256`
4. User approves in browser; Linear redirects to `klausemeister://oauth/callback?code=...&state=...`
5. App receives URL via `NSApplicationDelegate.application(_:open:)`, validates `state`, extracts `code`
6. Exchange code + `code_verifier` at `https://api.linear.app/oauth/token` (no `client_secret` with PKCE)
7. Store `access_token` and `refresh_token` in Keychain

### Token Lifecycle

- Access tokens expire in **24 hours**
- Refresh tokens are mandatory (Linear policy for apps created after Oct 2025)
- Refresh via `grant_type=refresh_token` at the same token endpoint
- 30-minute grace period on old refresh tokens handles network race conditions

### URL Scheme

Register `klausemeister` in Info.plist via `CFBundleURLTypes`. The callback continuation bridge uses `AsyncStream<URL>` or a stored `CheckedContinuation` on the live OAuthClient.

## Keychain Storage — TCA Dependency

```swift
struct KeychainClient: Sendable {
    var save: @Sendable (_ service: String, _ account: String, _ data: Data) async throws -> Void
    var load: @Sendable (_ service: String, _ account: String) async throws -> Data?
    var delete: @Sendable (_ service: String, _ account: String) async throws -> Void
}
```

- `liveValue`: wraps `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
- `testValue`: `unimplemented()` per TCA R3
- Service key: `"app.klausemeister"`
- Accounts: `"linear_access_token"`, `"linear_refresh_token"`

## OAuth Client — TCA Dependency

```swift
struct OAuthClient: Sendable {
    var authorize: @Sendable () async throws -> TokenResponse
    var refresh: @Sendable (_ refreshToken: String) async throws -> TokenResponse
    var revoke: @Sendable (_ accessToken: String) async throws -> Void
}

struct TokenResponse: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String
}
```

The `authorize` closure internally:
1. Generates `code_verifier` + `code_challenge`
2. Generates `state` nonce
3. Opens authorize URL via `NSWorkspace.shared.open`
4. Awaits callback URL via `CheckedContinuation` — app delegate receives URL, validates state, resumes continuation
5. Exchanges code + verifier at token endpoint via URLSession
6. Returns `TokenResponse`

`client_id` and `redirectURI` come from a `LinearConfig` enum — not hardcoded in the flow.

## Linear GraphQL Client — TCA Dependency

```swift
struct LinearAPIClient: Sendable {
    var me: @Sendable () async throws -> LinearUser
}

struct LinearUser: Equatable, Sendable {
    let id: String
    let name: String
    let email: String
}
```

- `liveValue`: uses swift-graphql's `URLRequest(url:).querying(selection)` against `https://api.linear.app/graphql`
- Auth header injected by reading access token from KeychainClient
- On 401, attempts token refresh via OAuthClient before failing
- `testValue`: `unimplemented()`
- `viewer` selection built with swift-graphql's generated DSL

### Codegen

- Commit Linear's `schema.graphql` snapshot (from `github.com/linear/linear`)
- Run swift-graphql CLI against it; output goes to `Linear/Generated/`
- Manual step, not a build phase

## LinearAuth Reducer

```swift
@Reducer
struct LinearAuthFeature {
    @ObservableState
    struct State: Equatable {
        var status: AuthStatus = .unauthenticated
        var user: LinearUser? = nil
    }

    enum AuthStatus: Equatable {
        case unauthenticated
        case authenticating
        case authenticated
        case failed(String)
    }

    enum Action: Equatable {
        case onAppear
        case loginButtonTapped
        case authCompleted(TaskResult<TokenResponse>)
        case meLoaded(TaskResult<LinearUser>)
        case logoutButtonTapped
        case logoutCompleted
    }

    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.keychainClient) var keychainClient
}
```

### Action Flow

1. **`onAppear`** — check Keychain for existing token; if found, fire `me()` to validate; if expired, attempt refresh
2. **`loginButtonTapped`** — set `.authenticating`, run `oauthClient.authorize()`, store tokens, fire `me()`
3. **`authCompleted`** — on success, store tokens and load user; on failure, set `.failed`
4. **`meLoaded`** — on success, set user + `.authenticated`; on failure, clear tokens, set `.unauthenticated`
5. **`logoutButtonTapped`** — delete tokens from Keychain, optionally revoke, reset state

### Composition

Always-present in AppFeature (checks Keychain on appear):

```swift
// AppFeature.State:
var linearAuth = LinearAuthFeature.State()

// AppFeature body:
Scope(state: \.linearAuth, action: \.linearAuth) { LinearAuthFeature() }
```

## File Layout

```
Klausemeister/
├── Linear/
│   ├── LinearConfig.swift              # clientID, redirectURI, endpoints
│   ├── LinearAuthFeature.swift         # TCA reducer for auth lifecycle
│   └── Generated/                      # swift-graphql codegen output
│       └── LinearAPI.swift
├── Dependencies/
│   ├── KeychainClient.swift            # Keychain dependency
│   ├── OAuthClient.swift               # OAuth + PKCE dependency
│   └── LinearAPIClient.swift           # GraphQL API dependency
├── AppFeature.swift                    # Add linearAuth scope
└── KlausemeisterApp.swift              # Add URL scheme handler
```

## Wiring Checklist

- Register `klausemeister` URL scheme in Info.plist (`CFBundleURLTypes`)
- Handle incoming URL in `KlausemeisterApp` — route `klausemeister://oauth/callback` to OAuthClient's continuation
- Add `swift-graphql` SPM dependency to Xcode project
- Commit Linear's `schema.graphql` snapshot, run codegen, commit output
- Scope `LinearAuthFeature` into `AppFeature`
- Add `linearAuth` action case to `AppFeature.Action`

## Verification

Auth is working when `LinearAuthFeature.State.user` is populated with a valid `LinearUser` (id + name) after the OAuth flow. Testable via `TestStore` with dependency overrides — no browser needed.
