import Testing
@testable import Klausemeister

@Test func `sendKeysArguments sends literal payload then submit key`() {
    let arguments = TmuxClient.sendKeysArguments(
        target: "klause-beta",
        keys: "$Klausemeister Next"
    )

    #expect(arguments == [
        ["send-keys", "-t", "klause-beta", "-l", "$Klausemeister Next"],
        ["send-keys", "-t", "klause-beta", "C-m"]
    ])
}
