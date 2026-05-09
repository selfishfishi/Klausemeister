import Testing
@testable import Klausemeister

@Test func `sendKeysArguments sends literal payload then submit key`() {
    let arguments = TmuxClient.sendKeysArguments(
        target: "klause-beta",
        keys: "/klause-next"
    )

    #expect(arguments == [
        ["send-keys", "-t", "klause-beta", "-l", "/klause-next"],
        ["send-keys", "-t", "klause-beta", "C-m"]
    ])
}
