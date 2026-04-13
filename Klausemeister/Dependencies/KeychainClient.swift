import Dependencies
import Foundation
import Security

struct KeychainClient {
    var save: @Sendable (_ service: String, _ account: String, _ data: Data) async throws -> Void
    var load: @Sendable (_ service: String, _ account: String) async throws -> Data?
    var delete: @Sendable (_ service: String, _ account: String) async throws -> Void
}

extension KeychainClient: DependencyKey {
    nonisolated static let liveValue = KeychainClient(
        save: { service, account, data in
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecAttrAccount as String: account
                    ]
                    SecItemDelete(deleteQuery as CFDictionary)

                    let addQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecAttrAccount as String: account,
                        kSecValueData as String: data
                    ]
                    let status = SecItemAdd(addQuery as CFDictionary, nil)
                    if status == errSecSuccess {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: KeychainError.saveFailed(status))
                    }
                }
            }
        },
        load: { service, account in
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecAttrAccount as String: account,
                        kSecReturnData as String: true,
                        kSecMatchLimit as String: kSecMatchLimitOne
                    ]
                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    if status == errSecSuccess {
                        continuation.resume(returning: result as? Data)
                    } else if status == errSecItemNotFound {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: KeychainError.loadFailed(status))
                    }
                }
            }
        },
        delete: { service, account in
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecAttrAccount as String: account
                    ]
                    let status = SecItemDelete(query as CFDictionary)
                    if status == errSecSuccess || status == errSecItemNotFound {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: KeychainError.deleteFailed(status))
                    }
                }
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
