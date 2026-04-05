# KLA-15: Linear API Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OAuth 2.0 (PKCE) authentication with Linear and verify it works via a `me` query — no UI.

**Architecture:** Three TCA dependencies (KeychainClient, OAuthClient, LinearAPIClient) orchestrated by a LinearAuthFeature reducer scoped into AppFeature. swift-graphql for type-safe GraphQL queries. URL scheme callback for OAuth redirect.

**Tech Stack:** Swift, TCA 1.25, SwiftGraphQL, Security.framework, URLSession

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `KlausemeisterTests/` (directory) | Create | Test target root |
| `KlausemeisterTests/KeychainClientTests.swift` | Create | Keychain integration tests |
| `KlausemeisterTests/LinearAuthFeatureTests.swift` | Create | Reducer tests via TestStore |
| `Klausemeister/Dependencies/KeychainClient.swift` | Create | Keychain read/write/delete TCA dependency |
| `Klausemeister/Dependencies/OAuthClient.swift` | Create | OAuth PKCE flow TCA dependency |
| `Klausemeister/Dependencies/LinearAPIClient.swift` | Create | GraphQL API TCA dependency |
| `Klausemeister/Linear/LinearConfig.swift` | Create | OAuth endpoints, client ID, redirect URI |
| `Klausemeister/Linear/LinearAuthFeature.swift` | Create | TCA reducer for auth lifecycle |
| `Klausemeister/Linear/LinearModels.swift` | Create | TokenResponse, LinearUser, OAuthError |
| `Klausemeister/Linear/Schema/linear-minimal.graphql` | Create | Minimal Linear schema for codegen |
| `Klausemeister/Linear/Generated/LinearAPI.swift` | Create | swift-graphql codegen output |
| `Klausemeister/AppFeature.swift` | Modify | Add linearAuth scope |
| `Klausemeister/KlausemeisterApp.swift` | Modify | Add onOpenURL handler + dependency wiring |
| `Klausemeister.xcodeproj/project.pbxproj` | Modify | Test target + SwiftGraphQL SPM dep |

---

### Task 1: Create test target

**Files:**
- Create: `KlausemeisterTests/KlausemeisterTests.swift`
- Modify: `Klausemeister.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create test directory and placeholder test**

```bash
mkdir -p KlausemeisterTests
```

```swift
// KlausemeisterTests/KlausemeisterTests.swift
import Testing
@testable import Klausemeister

@Test func appLaunches() {
    // Placeholder — verifies test target links against app target
    #expect(true)
}
```

- [ ] **Step 2: Add test target to project.pbxproj — build file**

In `Klausemeister.xcodeproj/project.pbxproj`, add to `/* Begin PBXBuildFile section */`:

```
A8TE000B2F816B35005797B3 /* ComposableArchitecture in Frameworks */ = {isa = PBXBuildFile; productRef = A8TE000C2F816B35005797B3 /* ComposableArchitecture */; };
```

- [ ] **Step 3: Add test product file reference**

Add to `/* Begin PBXFileReference section */`:

```
A8TE00012F816B35005797B3 /* KlausemeisterTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = KlausemeisterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

- [ ] **Step 4: Add test file system sync group**

Add new section after `/* End PBXFileSystemSynchronizedRootGroup section */` — or add entry within existing section:

```
A8TE00002F816B35005797B3 /* KlausemeisterTests */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = KlausemeisterTests;
    sourceTree = "<group>";
};
```

- [ ] **Step 5: Add test build phases**

Add to `/* Begin PBXFrameworksBuildPhase section */`:

```
A8TE00032F816B35005797B3 /* Frameworks */ = {
    isa = PBXFrameworksBuildPhase;
    buildActionMask = 2147483647;
    files = (
        A8TE000B2F816B35005797B3 /* ComposableArchitecture in Frameworks */,
    );
    runOnlyForDeploymentPostprocessing = 0;
};
```

Add to `/* Begin PBXSourcesBuildPhase section */`:

```
A8TE00022F816B35005797B3 /* Sources */ = {
    isa = PBXSourcesBuildPhase;
    buildActionMask = 2147483647;
    files = (
    );
    runOnlyForDeploymentPostprocessing = 0;
};
```

Add to `/* Begin PBXResourcesBuildPhase section */`:

```
A8TE00042F816B35005797B3 /* Resources */ = {
    isa = PBXResourcesBuildPhase;
    buildActionMask = 2147483647;
    files = (
    );
    runOnlyForDeploymentPostprocessing = 0;
};
```

- [ ] **Step 6: Add container item proxy and target dependency**

Add new sections:

```
/* Begin PBXContainerItemProxy section */
A8TE00072F816B35005797B3 /* PBXContainerItemProxy */ = {
    isa = PBXContainerItemProxy;
    containerPortal = A869EED82F816B35005797B3 /* Project object */;
    proxyType = 1;
    remoteGlobalIDString = A869EEDF2F816B35005797B3;
    remoteInfo = Klausemeister;
};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
A8TE00062F816B35005797B3 /* PBXTargetDependency */ = {
    isa = PBXTargetDependency;
    target = A869EEDF2F816B35005797B3 /* Klausemeister */;
    targetProxy = A8TE00072F816B35005797B3 /* PBXContainerItemProxy */;
};
/* End PBXTargetDependency section */
```

- [ ] **Step 7: Add test native target**

Add to `/* Begin PBXNativeTarget section */`:

```
A8TE00052F816B35005797B3 /* KlausemeisterTests */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = A8TE000A2F816B35005797B3 /* Build configuration list for PBXNativeTarget "KlausemeisterTests" */;
    buildPhases = (
        A8TE00022F816B35005797B3 /* Sources */,
        A8TE00032F816B35005797B3 /* Frameworks */,
        A8TE00042F816B35005797B3 /* Resources */,
    );
    buildRules = (
    );
    dependencies = (
        A8TE00062F816B35005797B3 /* PBXTargetDependency */,
    );
    fileSystemSynchronizedGroups = (
        A8TE00002F816B35005797B3 /* KlausemeisterTests */,
    );
    name = KlausemeisterTests;
    packageProductDependencies = (
        A8TE000C2F816B35005797B3 /* ComposableArchitecture */,
    );
    productName = KlausemeisterTests;
    productReference = A8TE00012F816B35005797B3 /* KlausemeisterTests.xctest */;
    productType = "com.apple.product-type.bundle.unit-test";
};
```

- [ ] **Step 8: Add test build configurations**

Add to `/* Begin XCBuildConfiguration section */`:

```
A8TE00082F816B35005797B3 /* Debug */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        BUNDLE_LOADER = "$(TEST_HOST)";
        CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 1;
        DEVELOPMENT_TEAM = 9QVJUYLZ2D;
        GENERATE_INFOPLIST_FILE = YES;
        MACOSX_DEPLOYMENT_TARGET = 26.4;
        MARKETING_VERSION = 1.0;
        PRODUCT_BUNDLE_IDENTIFIER = fish.selfish.klausemeister.KlausemeisterTests;
        PRODUCT_NAME = "$(TARGET_NAME)";
        SWIFT_APPROACHABLE_CONCURRENCY = YES;
        SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
        SWIFT_EMIT_LOC_STRINGS = NO;
        SWIFT_VERSION = 5.0;
        TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Klausemeister.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Klausemeister";
    };
    name = Debug;
};
A8TE00092F816B35005797B3 /* Release */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        BUNDLE_LOADER = "$(TEST_HOST)";
        CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 1;
        DEVELOPMENT_TEAM = 9QVJUYLZ2D;
        GENERATE_INFOPLIST_FILE = YES;
        MACOSX_DEPLOYMENT_TARGET = 26.4;
        MARKETING_VERSION = 1.0;
        PRODUCT_BUNDLE_IDENTIFIER = fish.selfish.klausemeister.KlausemeisterTests;
        PRODUCT_NAME = "$(TARGET_NAME)";
        SWIFT_APPROACHABLE_CONCURRENCY = YES;
        SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
        SWIFT_EMIT_LOC_STRINGS = NO;
        SWIFT_VERSION = 5.0;
        TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Klausemeister.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Klausemeister";
    };
    name = Release;
};
```

- [ ] **Step 9: Add test configuration list**

Add to `/* Begin XCConfigurationList section */`:

```
A8TE000A2F816B35005797B3 /* Build configuration list for PBXNativeTarget "KlausemeisterTests" */ = {
    isa = XCConfigurationList;
    buildConfigurations = (
        A8TE00082F816B35005797B3 /* Debug */,
        A8TE00092F816B35005797B3 /* Release */,
    );
    defaultConfigurationIsVisible = 0;
    defaultConfigurationName = Release;
};
```

- [ ] **Step 10: Add test TCA package dependency**

Add to `/* Begin XCSwiftPackageProductDependency section */`:

```
A8TE000C2F816B35005797B3 /* ComposableArchitecture */ = {
    isa = XCSwiftPackageProductDependency;
    package = A8TCA0002F816B35005797B3 /* XCRemoteSwiftPackageReference "swift-composable-architecture" */;
    productName = ComposableArchitecture;
};
```

- [ ] **Step 11: Update project groups and targets**

Update the root PBXGroup children to include the test group:

```
A869EED72F816B35005797B3 = {
    isa = PBXGroup;
    children = (
        A869EEE22F816B35005797B3 /* Klausemeister */,
        A8TE00002F816B35005797B3 /* KlausemeisterTests */,
        A869EEE12F816B35005797B3 /* Products */,
    );
    sourceTree = "<group>";
};
```

Update Products group:

```
A869EEE12F816B35005797B3 /* Products */ = {
    isa = PBXGroup;
    children = (
        A869EEE02F816B35005797B3 /* Klausemeister.app */,
        A8TE00012F816B35005797B3 /* KlausemeisterTests.xctest */,
    );
    name = Products;
    sourceTree = "<group>";
};
```

Update project targets array:

```
targets = (
    A869EEDF2F816B35005797B3 /* Klausemeister */,
    A8TE00052F816B35005797B3 /* KlausemeisterTests */,
);
```

- [ ] **Step 12: Build and verify test target works**

Run:
```bash
xcodebuild build-for-testing -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -5
```

If the scheme doesn't include tests yet, create/update the scheme to include KlausemeisterTests. Then:

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: Build succeeds, 1 test passes.

- [ ] **Step 13: Commit**

```bash
git add KlausemeisterTests/ Klausemeister.xcodeproj/
git commit -m "Add KlausemeisterTests unit test target"
```

---

### Task 2: KeychainClient TCA dependency

**Files:**
- Create: `Klausemeister/Dependencies/KeychainClient.swift`
- Test: `KlausemeisterTests/KeychainClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// KlausemeisterTests/KeychainClientTests.swift
import Testing
import Foundation
@testable import Klausemeister

@Test func keychainSaveAndLoad() async throws {
    let client = KeychainClient.liveValue
    let service = "test.klausemeister"
    let account = "test_token"
    let data = "test-access-token".data(using: .utf8)!

    // Clean up from any prior run
    try? await client.delete(service, account)

    try await client.save(service, account, data)
    let loaded = try await client.load(service, account)
    #expect(loaded == data)

    try await client.delete(service, account)
    let afterDelete = try await client.load(service, account)
    #expect(afterDelete == nil)
}
```

- [ ] **Step 2: Run test — verify it fails**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' -only-testing:KlausemeisterTests/KeychainClientTests 2>&1 | tail -10
```

Expected: FAIL — `KeychainClient` not found.

- [ ] **Step 3: Implement KeychainClient**

```swift
// Klausemeister/Dependencies/KeychainClient.swift
import Dependencies
import Foundation
import Security

struct KeychainClient: Sendable {
    var save: @Sendable (_ service: String, _ account: String, _ data: Data) async throws -> Void
    var load: @Sendable (_ service: String, _ account: String) async throws -> Data?
    var delete: @Sendable (_ service: String, _ account: String) async throws -> Void
}

extension KeychainClient: DependencyKey {
    nonisolated static let liveValue = KeychainClient(
        save: { service, account, data in
            // Delete existing item first to avoid errSecDuplicateItem
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.saveFailed(status)
            }
        },
        load: { service, account in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess else {
                if status == errSecItemNotFound { return nil }
                throw KeychainError.loadFailed(status)
            }
            return result as? Data
        },
        delete: { service, account in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.deleteFailed(status)
            }
        }
    )

    nonisolated static let testValue = KeychainClient(
        save: unimplemented("KeychainClient.save"),
        load: unimplemented("KeychainClient.load"),
        delete: unimplemented("KeychainClient.delete")
    )
}

enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

extension DependencyValues {
    var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' -only-testing:KlausemeisterTests/KeychainClientTests 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/Dependencies/KeychainClient.swift KlausemeisterTests/KeychainClientTests.swift
git commit -m "Add KeychainClient TCA dependency with Security.framework"
```

---

### Task 3: Linear models and config

**Files:**
- Create: `Klausemeister/Linear/LinearModels.swift`
- Create: `Klausemeister/Linear/LinearConfig.swift`

- [ ] **Step 1: Create Linear directory**

```bash
mkdir -p Klausemeister/Linear
```

- [ ] **Step 2: Create shared model types**

```swift
// Klausemeister/Linear/LinearModels.swift
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
```

- [ ] **Step 3: Create LinearConfig**

```swift
// Klausemeister/Linear/LinearConfig.swift
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
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/Linear/
git commit -m "Add LinearConfig and shared model types (TokenResponse, LinearUser, OAuthError)"
```

---

### Task 4: OAuthClient TCA dependency

**Files:**
- Create: `Klausemeister/Dependencies/OAuthClient.swift`

- [ ] **Step 1: Create OAuthClient**

This is the most complex dependency. The `authorize` closure runs the full PKCE flow. The `handleCallback` closure bridges the URL scheme callback to the suspended `authorize` call.

```swift
// Klausemeister/Dependencies/OAuthClient.swift
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

private func exchangeCode(_ code: String, codeVerifier: String) async throws -> TokenResponse {
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

private func decodeTokenResponse(_ data: Data) throws -> TokenResponse {
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
    func base64URLEncoded() -> String {
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
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Dependencies/OAuthClient.swift
git commit -m "Add OAuthClient TCA dependency with PKCE flow"
```

---

### Task 5: URL scheme registration and app handler

**Files:**
- Modify: `Klausemeister.xcodeproj/project.pbxproj`
- Modify: `Klausemeister/KlausemeisterApp.swift`
- Modify: `Klausemeister/AppFeature.swift`

- [ ] **Step 1: Register URL scheme in build settings**

The project uses `GENERATE_INFOPLIST_FILE = YES`, so add URL scheme via build settings. In `project.pbxproj`, add to **both** Debug and Release build configurations for the `Klausemeister` native target (IDs `A869EEEC2F816B35005797B3` and `A869EEED2F816B35005797B3`):

```
INFOPLIST_KEY_CFBundleURLTypes = (
    {
        CFBundleURLName = "OAuth Callback";
        CFBundleURLSchemes = (
            klausemeister,
        );
    },
);
```

Add this line after `INFOPLIST_KEY_NSHumanReadableCopyright = "";` in both configs.

- [ ] **Step 2: Add oauthCallbackReceived action to AppFeature**

In `Klausemeister/AppFeature.swift`, add to `enum Action`:

```swift
case oauthCallbackReceived(URL)
```

Add the dependency and handler in the `Reduce` closure:

```swift
@Dependency(\.oauthClient) var oauthClient
```

And add the case in the switch:

```swift
case let .oauthCallbackReceived(url):
    return .run { [oauthClient] _ in
        oauthClient.handleCallback(url)
    }
```

- [ ] **Step 3: Add onOpenURL handler in KlausemeisterApp**

In `Klausemeister/KlausemeisterApp.swift`, add `.onOpenURL` to the `WindowGroup`:

```swift
WindowGroup {
    TerminalContainerView(store: store, surfaceStore: surfaceStore)
}
.defaultSize(width: 900, height: 600)
.handlesExternalEvents(matching: ["klausemeister"])
.onOpenURL { url in
    store.send(.oauthCallbackReceived(url))
}
```

Note: `.onOpenURL` is a Scene modifier. Place it after `.defaultSize`.

- [ ] **Step 4: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Klausemeister.xcodeproj/ Klausemeister/AppFeature.swift Klausemeister/KlausemeisterApp.swift
git commit -m "Register klausemeister:// URL scheme and wire OAuth callback to AppFeature"
```

---

### Task 6: swift-graphql SPM dependency and codegen

**Files:**
- Modify: `Klausemeister.xcodeproj/project.pbxproj`
- Create: `Klausemeister/Linear/Schema/linear-minimal.graphql`
- Create: `Klausemeister/Linear/Generated/LinearAPI.swift`

- [ ] **Step 1: Add SwiftGraphQL SPM package to project.pbxproj**

Add to `/* Begin XCRemoteSwiftPackageReference section */`:

```
A8SG00002F816B35005797B3 /* XCRemoteSwiftPackageReference "swift-graphql" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/maticzav/swift-graphql.git";
    requirement = {
        kind = upToNextMajorVersion;
        minimumVersion = 5.0.0;
    };
};
```

Add to `/* Begin XCSwiftPackageProductDependency section */`:

```
A8SG00012F816B35005797B3 /* SwiftGraphQL */ = {
    isa = XCSwiftPackageProductDependency;
    package = A8SG00002F816B35005797B3 /* XCRemoteSwiftPackageReference "swift-graphql" */;
    productName = SwiftGraphQL;
};
A8SG00022F816B35005797B3 /* SwiftGraphQLClient */ = {
    isa = XCSwiftPackageProductDependency;
    package = A8SG00002F816B35005797B3 /* XCRemoteSwiftPackageReference "swift-graphql" */;
    productName = SwiftGraphQLClient;
};
```

Add to `/* Begin PBXBuildFile section */`:

```
A8SG00032F816B35005797B3 /* SwiftGraphQL in Frameworks */ = {isa = PBXBuildFile; productRef = A8SG00012F816B35005797B3 /* SwiftGraphQL */; };
A8SG00042F816B35005797B3 /* SwiftGraphQLClient in Frameworks */ = {isa = PBXBuildFile; productRef = A8SG00022F816B35005797B3 /* SwiftGraphQLClient */; };
```

Add to app target's frameworks build phase (`A869EEDD2F816B35005797B3`):

```
A8SG00032F816B35005797B3 /* SwiftGraphQL in Frameworks */,
A8SG00042F816B35005797B3 /* SwiftGraphQLClient in Frameworks */,
```

Add to app target's `packageProductDependencies`:

```
A8SG00012F816B35005797B3 /* SwiftGraphQL */,
A8SG00022F816B35005797B3 /* SwiftGraphQLClient */,
```

Add to project's `packageReferences`:

```
A8SG00002F816B35005797B3 /* XCRemoteSwiftPackageReference "swift-graphql" */,
```

- [ ] **Step 2: Resolve packages and verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: Resolves SwiftGraphQL package, BUILD SUCCEEDED.

- [ ] **Step 3: Create minimal Linear schema**

```bash
mkdir -p Klausemeister/Linear/Schema
```

```graphql
# Klausemeister/Linear/Schema/linear-minimal.graphql
# Minimal subset of Linear's GraphQL schema for Klausemeister MVP.
# Full schema: https://github.com/linear/linear/blob/master/packages/sdk/src/schema.graphql

type Query {
  "The currently authenticated user."
  viewer: User!
}

"A user account."
type User {
  "The unique identifier of the entity."
  id: ID!
  "The user's full name."
  name: String!
  "The user's email address."
  email: String!
}
```

- [ ] **Step 4: Run swift-graphql codegen**

Install the CLI if needed and run codegen:

```bash
# Install via Homebrew (if not already available)
brew install swift-graphql 2>/dev/null || npx swift-graphql-codegen 2>/dev/null || echo "CLI not found — use manual fallback"

# Run codegen against minimal schema
mkdir -p Klausemeister/Linear/Generated
swift-graphql Klausemeister/Linear/Schema/linear-minimal.graphql --output Klausemeister/Linear/Generated/LinearAPI.swift
```

If the CLI is unavailable, create the generated file manually based on the swift-graphql DSL patterns. The codegen output provides type-safe selection builders. For the minimal schema, verify the generated file contains selection types for `Query` and `User` with field accessors for `id`, `name`, and `email`.

If codegen produces errors or the CLI cannot be installed, write the selection code manually using SwiftGraphQL's API — see Task 7 Step 3 for the fallback approach.

- [ ] **Step 5: Verify build with generated code**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Klausemeister.xcodeproj/ Klausemeister/Linear/Schema/ Klausemeister/Linear/Generated/
git commit -m "Add SwiftGraphQL SPM dependency and Linear schema codegen"
```

---

### Task 7: LinearAPIClient TCA dependency

**Files:**
- Create: `Klausemeister/Dependencies/LinearAPIClient.swift`

- [ ] **Step 1: Create LinearAPIClient**

```swift
// Klausemeister/Dependencies/LinearAPIClient.swift
import Dependencies
import Foundation
import SwiftGraphQL
import SwiftGraphQLClient

struct LinearAPIClient: Sendable {
    var me: @Sendable () async throws -> LinearUser
}

extension LinearAPIClient: DependencyKey {
    nonisolated static let liveValue: LinearAPIClient = {
        @Dependency(\.keychainClient) var keychainClient

        return LinearAPIClient(
            me: {
                // Load access token from Keychain
                guard let tokenData = try await keychainClient.load(
                    LinearConfig.keychainService,
                    LinearConfig.accessTokenAccount
                ), let token = String(data: tokenData, encoding: .utf8) else {
                    throw OAuthError.unauthorized
                }

                // Build the viewer query using swift-graphql selections
                // The exact API depends on the codegen output.
                // This uses the generated selection builders:
                let query = """
                query { viewer { id name email } }
                """

                var request = URLRequest(url: LinearConfig.graphqlURL)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                struct GraphQLRequest: Encodable {
                    let query: String
                }
                request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query))

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OAuthError.networkError
                }
                if httpResponse.statusCode == 401 {
                    throw OAuthError.unauthorized
                }

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
                let graphQLResponse = try JSONDecoder().decode(GraphQLResponse.self, from: data)
                return LinearUser(
                    id: graphQLResponse.data.viewer.id,
                    name: graphQLResponse.data.viewer.name,
                    email: graphQLResponse.data.viewer.email
                )
            }
        )
    }()

    nonisolated static let testValue = LinearAPIClient(
        me: unimplemented("LinearAPIClient.me")
    )
}

extension DependencyValues {
    var linearAPIClient: LinearAPIClient {
        get { self[LinearAPIClient.self] }
        set { self[LinearAPIClient.self] = newValue }
    }
}
```

**Note:** The `liveValue` above uses raw URLSession as a baseline. Once the swift-graphql codegen output is verified (Task 6), refactor the `me` closure to use the generated SwiftGraphQL selection builders and `SwiftGraphQLClient.Client` instead of the raw query string. The interface (`var me: @Sendable () async throws -> LinearUser`) stays the same regardless.

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Dependencies/LinearAPIClient.swift
git commit -m "Add LinearAPIClient TCA dependency for GraphQL viewer query"
```

---

### Task 8: LinearAuthFeature reducer

**Files:**
- Create: `Klausemeister/Linear/LinearAuthFeature.swift`
- Test: `KlausemeisterTests/LinearAuthFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// KlausemeisterTests/LinearAuthFeatureTests.swift
import ComposableArchitecture
import Testing
@testable import Klausemeister

@Test func loginFlowSuccess() async {
    let testToken = TokenResponse(
        accessToken: "lin_oauth_test",
        refreshToken: "refresh_test",
        expiresIn: 86399,
        scope: "read"
    )
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { testToken }
        $0.keychainClient.save = { _, _, _ in }
        $0.linearAPIClient.me = { testUser }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.success) // stores tokens, fires me()
    await store.receive(\.meLoaded.success) {
        $0.status = .authenticated
        $0.user = testUser
    }
}

@Test func loginFlowAuthFailure() async {
    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { throw OAuthError.stateMismatch }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.failure) {
        $0.status = .failed("stateMismatch")
    }
}

@Test func loginFlowMeFailure() async {
    let testToken = TokenResponse(
        accessToken: "lin_oauth_test",
        refreshToken: "refresh_test",
        expiresIn: 86399,
        scope: "read"
    )

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.oauthClient.authorize = { testToken }
        $0.keychainClient.save = { _, _, _ in }
        $0.keychainClient.delete = { _, _ in }
        $0.linearAPIClient.me = { throw OAuthError.unauthorized }
    }

    await store.send(.loginButtonTapped) {
        $0.status = .authenticating
    }
    await store.receive(\.authCompleted.success) // stores tokens, fires me()
    await store.receive(\.meLoaded.failure) {
        $0.status = .unauthenticated
    }
}

@Test func existingTokenOnAppear() async {
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")
    let tokenData = "existing_token".data(using: .utf8)!

    let store = TestStore(initialState: LinearAuthFeature.State()) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.load = { _, account in
            if account == LinearConfig.accessTokenAccount { return tokenData }
            return nil
        }
        $0.linearAPIClient.me = { testUser }
    }

    await store.send(.onAppear) {
        $0.status = .authenticating
    }
    await store.receive(\.meLoaded.success) {
        $0.status = .authenticated
        $0.user = testUser
    }
}

@Test func logoutFlow() async {
    let testUser = LinearUser(id: "user-1", name: "Ali", email: "ali@test.com")

    let store = TestStore(
        initialState: LinearAuthFeature.State(
            status: .authenticated,
            user: testUser
        )
    ) {
        LinearAuthFeature()
    } withDependencies: {
        $0.keychainClient.delete = { _, _ in }
    }

    await store.send(.logoutButtonTapped) {
        $0.status = .unauthenticated
        $0.user = nil
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' -only-testing:KlausemeisterTests/LinearAuthFeatureTests 2>&1 | tail -10
```

Expected: FAIL — `LinearAuthFeature` not found.

- [ ] **Step 3: Implement LinearAuthFeature**

```swift
// Klausemeister/Linear/LinearAuthFeature.swift
import ComposableArchitecture
import Foundation

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
    }

    private enum CancelID {
        case authFlow
    }

    @Dependency(\.oauthClient) var oauthClient
    @Dependency(\.linearAPIClient) var linearAPIClient
    @Dependency(\.keychainClient) var keychainClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.status = .authenticating
                return .run { send in
                    // Check for existing token
                    let tokenData = try? await keychainClient.load(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount
                    )
                    guard tokenData != nil else {
                        await send(.meLoaded(.failure(OAuthError.unauthorized)))
                        return
                    }
                    // Validate by calling me()
                    await send(.meLoaded(TaskResult { try await linearAPIClient.me() }))
                }

            case .loginButtonTapped:
                state.status = .authenticating
                return .run { send in
                    await send(.authCompleted(TaskResult { try await oauthClient.authorize() }))
                }
                .cancellable(id: CancelID.authFlow, cancelInFlight: true)

            case let .authCompleted(.success(token)):
                return .run { send in
                    // Store tokens in Keychain
                    try await keychainClient.save(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount,
                        Data(token.accessToken.utf8)
                    )
                    try await keychainClient.save(
                        LinearConfig.keychainService,
                        LinearConfig.refreshTokenAccount,
                        Data(token.refreshToken.utf8)
                    )
                    // Verify auth by fetching current user
                    await send(.meLoaded(TaskResult { try await linearAPIClient.me() }))
                }

            case let .authCompleted(.failure(error)):
                state.status = .failed(String(describing: error))
                return .none

            case let .meLoaded(.success(user)):
                state.status = .authenticated
                state.user = user
                return .none

            case .meLoaded(.failure):
                state.status = .unauthenticated
                state.user = nil
                return .run { _ in
                    // Clear invalid tokens
                    try? await keychainClient.delete(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount
                    )
                    try? await keychainClient.delete(
                        LinearConfig.keychainService,
                        LinearConfig.refreshTokenAccount
                    )
                }

            case .logoutButtonTapped:
                state.status = .unauthenticated
                state.user = nil
                return .run { _ in
                    try? await keychainClient.delete(
                        LinearConfig.keychainService,
                        LinearConfig.accessTokenAccount
                    )
                    try? await keychainClient.delete(
                        LinearConfig.keychainService,
                        LinearConfig.refreshTokenAccount
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' -only-testing:KlausemeisterTests/LinearAuthFeatureTests 2>&1 | tail -10
```

Expected: All 5 tests PASS.

**Troubleshooting:** If tests fail due to `TaskResult` matching issues, adjust the `store.receive` patterns. TCA's `TaskResult` wraps errors as `Error` (type-erased), so pattern matching uses `\.authCompleted.success` and `\.authCompleted.failure` key paths.

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/Linear/LinearAuthFeature.swift KlausemeisterTests/LinearAuthFeatureTests.swift
git commit -m "Add LinearAuthFeature reducer with full auth lifecycle tests"
```

---

### Task 9: Wire into AppFeature and final verification

**Files:**
- Modify: `Klausemeister/AppFeature.swift`
- Modify: `Klausemeister/KlausemeisterApp.swift`

- [ ] **Step 1: Add LinearAuthFeature scope to AppFeature**

In `Klausemeister/AppFeature.swift`:

Add `linearAuth` to State:

```swift
@ObservableState
struct State: Equatable {
    var tabs: IdentifiedArrayOf<Tab> = []
    var activeTabID: UUID?
    var showSidebar: Bool = true
    var linearAuth = LinearAuthFeature.State()

    // ... Tab struct unchanged
}
```

Add `linearAuth` to Action (note: `oauthCallbackReceived` was already added in Task 5):

```swift
enum Action {
    // ... existing cases unchanged
    case linearAuth(LinearAuthFeature.Action)
    case oauthCallbackReceived(URL) // already present from Task 5
}
```

Add `Scope` to reducer body — **before** the existing `Reduce`:

```swift
var body: some Reducer<State, Action> {
    Scope(state: \.linearAuth, action: \.linearAuth) {
        LinearAuthFeature()
    }
    Reduce { state, action in
        // ... existing switch unchanged
    }
}
```

- [ ] **Step 2: Wire OAuthClient dependency in KlausemeisterApp**

In `Klausemeister/KlausemeisterApp.swift`, no additional dependency wiring is needed — `OAuthClient.liveValue` is statically defined and the TCA dependency system resolves it automatically.

Verify the `onOpenURL` modifier was added in Task 5. If not, add it now.

- [ ] **Step 3: Run full build**

```bash
xcodebuild build -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project Klausemeister.xcodeproj -scheme Klausemeister -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: All tests pass (placeholder test + Keychain test + 5 reducer tests = 7 tests).

- [ ] **Step 5: Commit**

```bash
git add Klausemeister/AppFeature.swift Klausemeister/KlausemeisterApp.swift
git commit -m "Wire LinearAuthFeature into AppFeature with OAuth callback routing"
```

- [ ] **Step 6: Final verification commit**

If any fixes were needed during build/test, commit them:

```bash
git add -A
git commit -m "Fix build/test issues from Linear API integration wiring"
```

Skip this step if Steps 3-4 passed cleanly.
