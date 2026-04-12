import Dependencies
import Foundation
import Testing
@testable import Klausemeister

@Test func `ensureRunning skips respawn when session exists with non-shell foreground`() async throws {
    let hasSessionCalls = LockIsolated<[String]>([])
    let createCalls = LockIsolated<Int>(0)
    let sendKeysCalls = LockIsolated<Int>(0)

    let tmux = TmuxClient(
        createSession: { _, _, _ in
            createCalls.withValue { $0 += 1 }
        },
        sendKeys: { _, _ in
            sendKeysCalls.withValue { $0 += 1 }
        },
        hasSession: { name in
            hasSessionCalls.withValue { $0.append(name) }
            return true
        },
        killSession: { _ in },
        listSessions: { [] },
        firstWindowCommand: { _ in "node" },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )
    let client = MeisterClient.live(tmux: tmux)
    try await client.ensureRunning("wt-1", "/tmp/worktree", "klause-example")

    #expect(hasSessionCalls.value == ["klause-example"])
    #expect(createCalls.value == 0)
    #expect(sendKeysCalls.value == 0)
}

@Test func `ensureRunning respawns claude when session exists with shell foreground`() async throws {
    let createCalls = LockIsolated<Int>(0)
    let sendKeysTarget = LockIsolated<String?>(nil)
    let sendKeysBody = LockIsolated<String?>(nil)

    let tmux = TmuxClient(
        createSession: { _, _, _ in
            createCalls.withValue { $0 += 1 }
        },
        sendKeys: { target, keys in
            sendKeysTarget.setValue(target)
            sendKeysBody.setValue(keys)
        },
        hasSession: { _ in true },
        killSession: { _ in },
        listSessions: { [] },
        firstWindowCommand: { _ in "zsh" },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )
    let client = MeisterClient.live(tmux: tmux)
    try await client.ensureRunning("wt-1", "/tmp/worktree", "klause-example")

    #expect(createCalls.value == 0)
    #expect(sendKeysTarget.value == "=klause-example")
    #expect(sendKeysBody.value?.hasSuffix("claude") == true)
}

@Test func `ensureRunning creates session with env vars when missing`() async throws {
    let envSeen = LockIsolated<[String: String]>([:])
    let sessionSeen = LockIsolated<String?>(nil)
    let sendKeysTarget = LockIsolated<String?>(nil)
    let sendKeysBody = LockIsolated<String?>(nil)

    let tmux = TmuxClient(
        createSession: { name, _, env in
            sessionSeen.setValue(name)
            envSeen.setValue(env)
        },
        sendKeys: { target, keys in
            sendKeysTarget.setValue(target)
            sendKeysBody.setValue(keys)
        },
        hasSession: { _ in false },
        killSession: { _ in },
        listSessions: { [] },
        firstWindowCommand: { _ in nil },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )
    let client = MeisterClient.live(tmux: tmux)
    try await client.ensureRunning("wt-1", "/tmp/worktree", "klause-example")

    #expect(sessionSeen.value == "klause-example")
    #expect(envSeen.value["KLAUSE_MEISTER"] == "1")
    #expect(envSeen.value["KLAUSE_WORKTREE_ID"] == "wt-1")
    #expect(sendKeysTarget.value == "=klause-example")
    // The send-keys body is either an absolute claude path (probed at
    // construction time) or the bare name — either way it must end in
    // `claude`.
    #expect(sendKeysBody.value?.hasSuffix("claude") == true)
}

@Test func `teardown forwards to killSession`() async throws {
    let killed = LockIsolated<String?>(nil)

    let tmux = TmuxClient(
        createSession: { _, _, _ in },
        sendKeys: { _, _ in },
        hasSession: { _ in false },
        killSession: { name in killed.setValue(name) },
        listSessions: { [] },
        firstWindowCommand: { _ in nil },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )
    let client = MeisterClient.live(tmux: tmux)
    try await client.teardown("klause-example")

    #expect(killed.value == "klause-example")
}
