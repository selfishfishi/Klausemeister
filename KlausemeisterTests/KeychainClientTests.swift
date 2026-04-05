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
