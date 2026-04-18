import Dependencies
import Foundation

/// Thin wrapper over `UserDefaults.standard` so reducers can be tested
/// without reaching into global state. Keep the surface small: only add
/// a new closure when a reducer actually needs it.
struct UserDefaultsClient {
    /// Read a boolean value for `key`. Returns `false` when the key is
    /// missing — mirrors `UserDefaults.bool(forKey:)`.
    var bool: @Sendable (_ key: String) -> Bool

    /// Write a boolean value for `key`.
    var setBool: @Sendable (_ value: Bool, _ key: String) -> Void

    /// Read a string value for `key`, or `nil` when missing.
    var string: @Sendable (_ key: String) -> String?

    /// Write a string value for `key`. Passing `nil` removes the key.
    var setString: @Sendable (_ value: String?, _ key: String) -> Void
}

extension UserDefaultsClient: DependencyKey {
    nonisolated static let liveValue = UserDefaultsClient(
        bool: { key in UserDefaults.standard.bool(forKey: key) },
        setBool: { value, key in UserDefaults.standard.set(value, forKey: key) },
        string: { key in UserDefaults.standard.string(forKey: key) },
        setString: { value, key in
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    )

    nonisolated static let testValue = UserDefaultsClient(
        bool: unimplemented("UserDefaultsClient.bool", placeholder: false),
        setBool: unimplemented("UserDefaultsClient.setBool"),
        string: unimplemented("UserDefaultsClient.string", placeholder: nil),
        setString: unimplemented("UserDefaultsClient.setString")
    )
}

extension DependencyValues {
    var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}
