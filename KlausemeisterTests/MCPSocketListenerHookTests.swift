import Foundation
import Testing
@testable import Klausemeister

@Test func `codex hook upsert removes duplicate Klausemeister hooks but preserves approvals`() {
    let hookPath = MCPSocketListener.statusHookSymlinkPath
    let existing = """
    model = "gpt-5.5"

    [[hooks.SessionStart]]
    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "\(hookPath)"

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "\(hookPath)"
    # klausemeister-hooks-managed-block:end

    # klausemeister-hooks-managed-block:begin (do not edit — overwritten by app)
    [[hooks.SessionStart]]
    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "\(hookPath)"

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "\(hookPath)"

    [hooks.state]

    [hooks.state."/Users/alifathalian/.codex/config.toml:session_start:0:0"]
    trusted_hash = "sha256:abc"

    [apps.example]
    approval_mode = "approve"
    # klausemeister-hooks-managed-block:end
    """

    let updated = MCPSocketListener.upsertCodexHooksBlock(in: existing)

    #expect(occurrenceCount(of: "command = \"\(hookPath)\"", in: updated) == 6)
    #expect(occurrenceCount(of: "[[hooks.SessionStart]]", in: updated) == 1)
    #expect(occurrenceCount(of: "[[hooks.Stop]]", in: updated) == 1)
    #expect(updated.contains("[hooks.state]"))
    #expect(updated.contains("trusted_hash = \"sha256:abc\""))
    #expect(updated.contains("[apps.example]"))
    #expect(!updated.contains("# klausemeister-hooks-managed-block:end"))
}

@Test func `codex hook upsert is idempotent`() {
    let once = MCPSocketListener.upsertCodexHooksBlock(in: "model = \"gpt-5.5\"\n")
    let twice = MCPSocketListener.upsertCodexHooksBlock(in: once)

    #expect(twice == once)
}

@Test func `codex hook upsert preserves user authored hooks`() {
    let hookPath = MCPSocketListener.statusHookSymlinkPath
    let existing = """
    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "/tmp/custom-stop-hook.sh"

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "\(hookPath)"
    """

    let updated = MCPSocketListener.upsertCodexHooksBlock(in: existing)

    #expect(updated.contains("command = \"/tmp/custom-stop-hook.sh\""))
    #expect(occurrenceCount(of: "command = \"\(hookPath)\"", in: updated) == 6)
    #expect(occurrenceCount(of: "[[hooks.Stop]]", in: updated) == 2)
}

private func occurrenceCount(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}
