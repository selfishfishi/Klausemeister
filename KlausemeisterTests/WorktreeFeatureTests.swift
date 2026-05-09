import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

// MARK: - Fixtures

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func makeWorktree(
    id: String = "w1",
    meisterSessionState: MeisterSessionState = .working(tool: nil),
    meisterStatusText: String? = nil,
    meisterActivityText: String? = nil,
    meisterActivityUpdatedAt: Date? = nil,
    agent: MeisterAgent = .claude
) -> Worktree {
    var worktree = Worktree(
        id: id,
        name: "Alpha",
        gitWorktreePath: "/tmp/\(id)",
        sortOrder: 0
    )
    worktree.meisterSessionState = meisterSessionState
    worktree.meisterStatusText = meisterStatusText
    worktree.meisterActivityText = meisterActivityText
    worktree.meisterActivityUpdatedAt = meisterActivityUpdatedAt
    worktree.agent = agent
    return worktree
}

private func makeStore(
    worktree: Worktree,
    clock: TestClock<Duration> = TestClock()
) -> TestStoreOf<WorktreeFeature> {
    TestStore(
        initialState: WorktreeFeature.State(
            worktrees: IdentifiedArrayOf(uniqueElements: [worktree])
        )
    ) {
        WorktreeFeature()
    } withDependencies: {
        $0.date = .constant(fixedDate)
        $0.continuousClock = clock
    }
}

// MARK: - meisterActivityTextChanged

@Test func `meisterActivityTextChanged stamps text and timestamp, schedules TTL`() async {
    let clock = TestClock()
    let store = makeStore(worktree: makeWorktree(), clock: clock)

    await store.send(.meisterActivityTextChanged(worktreeId: "w1", text: "reading foo.swift")) {
        $0.worktrees[id: "w1"]?.meisterActivityText = "reading foo.swift"
        $0.worktrees[id: "w1"]?.meisterActivityUpdatedAt = fixedDate
    }

    // TTL effect clears the slot once it elapses on the injected clock.
    await clock.advance(by: .seconds(61))
    await store.receive(\.meisterActivityExpired) {
        $0.worktrees[id: "w1"]?.meisterActivityText = nil
        $0.worktrees[id: "w1"]?.meisterActivityUpdatedAt = nil
    }
}

// MARK: - meisterSessionStateChanged → .offline wipes activity

@Test func `meisterSessionStateChanged to offline clears activity fields and cancels TTL`() async {
    let clock = TestClock()
    let store = makeStore(
        worktree: makeWorktree(
            meisterSessionState: .working(tool: "Edit"),
            meisterStatusText: "klause-execute — drafting plan",
            meisterActivityText: "reading foo.swift",
            meisterActivityUpdatedAt: fixedDate
        ),
        clock: clock
    )

    await store.send(.meisterSessionStateChanged(worktreeId: "w1", state: .offline)) {
        $0.worktrees[id: "w1"]?.meisterSessionState = .offline
        $0.worktrees[id: "w1"]?.meisterStatusText = nil
        $0.worktrees[id: "w1"]?.meisterActivityText = nil
        $0.worktrees[id: "w1"]?.meisterActivityUpdatedAt = nil
    }
}

// MARK: - Non-offline transitions preserve progress and activity

@Test(arguments: [MeisterSessionState.idle, .blocked, .error])
func `non-offline transitions preserve progressText and activity`(nextState: MeisterSessionState) async {
    let clock = TestClock()
    let store = makeStore(
        worktree: makeWorktree(
            meisterSessionState: .working(tool: "Bash"),
            meisterStatusText: "klause-execute — running tests",
            meisterActivityText: "waiting on user feedback",
            meisterActivityUpdatedAt: fixedDate
        ),
        clock: clock
    )

    await store.send(.meisterSessionStateChanged(worktreeId: "w1", state: nextState)) {
        $0.worktrees[id: "w1"]?.meisterSessionState = nextState
        // Progress and activity text intentionally remain visible for
        // idle/blocked/error transitions; only offline clears them.
    }
}

// MARK: - command rendering

@Test func `meister command rendering is agent aware`() {
    #expect(MeisterAgent.claude.commandText(for: .next) == "/klause-workflow:klause-next")
    #expect(MeisterAgent.codex.commandText(for: .next) == "$Klausemeister Next")
    #expect(MeisterAgent.claude.commandText(for: .workflow(.openPR)) == "/klause-workflow:klause-open-pr")
    #expect(MeisterAgent.codex.commandText(for: .workflow(.openPR)) == "$Klausemeister Open PR")
    #expect(MeisterAgent.claude.commandText(for: .workflow(.complete)) == nil)
    #expect(MeisterAgent.codex.commandText(for: .workflow(.complete)) == nil)
}

@Test func `sendMeisterCommandRequested renders Codex next skill and forwards to tmux session`() async {
    var worktree = makeWorktree(id: "w1", meisterSessionState: .idle, agent: .codex)
    worktree.repoName = "Main Repo"
    let sentTarget = LockIsolated<String?>(nil)
    let sentKeys = LockIsolated<String?>(nil)
    let store = makeStore(worktree: worktree)
    store.dependencies.tmuxClient = TmuxClient(
        createSession: { _, _, _ in },
        sendKeys: { target, keys in
            sentTarget.setValue(target)
            sentKeys.setValue(keys)
        },
        hasSession: { _ in false },
        killSession: { _ in },
        listSessions: { [] },
        firstWindowCommand: { _ in nil },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )

    await store.send(.sendMeisterCommandRequested(
        worktreeId: "w1",
        command: .next
    ))
    await store.finish()

    #expect(sentTarget.value == "klause-main-repo-alpha")
    #expect(sentKeys.value == "$Klausemeister Next")
}

@Test func `sendMeisterCommandRequested renders Claude workflow command and forwards to tmux session`() async {
    var worktree = makeWorktree(id: "w1", meisterSessionState: .idle, agent: .claude)
    worktree.repoName = "Main Repo"
    let sentTarget = LockIsolated<String?>(nil)
    let sentKeys = LockIsolated<String?>(nil)
    let store = makeStore(worktree: worktree)
    store.dependencies.tmuxClient = TmuxClient(
        createSession: { _, _, _ in },
        sendKeys: { target, keys in
            sentTarget.setValue(target)
            sentKeys.setValue(keys)
        },
        hasSession: { _ in false },
        killSession: { _ in },
        listSessions: { [] },
        firstWindowCommand: { _ in nil },
        resolvedTmuxPath: { "/opt/homebrew/bin/tmux" }
    )

    await store.send(.sendMeisterCommandRequested(
        worktreeId: "w1",
        command: .workflow(.pull)
    ))
    await store.finish()

    #expect(sentTarget.value == "klause-main-repo-alpha")
    #expect(sentKeys.value == "/klause-workflow:klause-pull")
}
