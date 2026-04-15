import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

// MARK: - Fixtures

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func makeWorktree(
    id: String = "w1",
    claudeStatus: ClaudeSessionState = .working(tool: nil),
    claudeStatusText: String? = nil,
    claudeActivityText: String? = nil,
    claudeActivityUpdatedAt: Date? = nil
) -> Worktree {
    var worktree = Worktree(
        id: id,
        name: "Alpha",
        sortOrder: 0,
        gitWorktreePath: "/tmp/\(id)"
    )
    worktree.claudeStatus = claudeStatus
    worktree.claudeStatusText = claudeStatusText
    worktree.claudeActivityText = claudeActivityText
    worktree.claudeActivityUpdatedAt = claudeActivityUpdatedAt
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

// MARK: - claudeActivityTextChanged

@Test func `claudeActivityTextChanged stamps text and timestamp, schedules TTL`() async {
    let clock = TestClock()
    let store = makeStore(worktree: makeWorktree(), clock: clock)

    await store.send(.claudeActivityTextChanged(worktreeId: "w1", text: "reading foo.swift")) {
        $0.worktrees[id: "w1"]?.claudeActivityText = "reading foo.swift"
        $0.worktrees[id: "w1"]?.claudeActivityUpdatedAt = fixedDate
    }

    // TTL effect clears the slot once 30s elapse on the injected clock.
    await clock.advance(by: .seconds(31))
    await store.receive(\.claudeActivityExpired) {
        $0.worktrees[id: "w1"]?.claudeActivityText = nil
        $0.worktrees[id: "w1"]?.claudeActivityUpdatedAt = nil
    }
}

// MARK: - claudeStatusChanged → .offline wipes activity

@Test func `claudeStatusChanged to offline clears activity fields and cancels TTL`() async {
    let clock = TestClock()
    let store = makeStore(
        worktree: makeWorktree(
            claudeStatus: .working(tool: "Edit"),
            claudeStatusText: "klause-execute — drafting plan",
            claudeActivityText: "reading foo.swift",
            claudeActivityUpdatedAt: fixedDate
        ),
        clock: clock
    )

    await store.send(.claudeStatusChanged(worktreeId: "w1", state: .offline)) {
        $0.worktrees[id: "w1"]?.claudeStatus = .offline
        $0.worktrees[id: "w1"]?.claudeStatusText = nil
        $0.worktrees[id: "w1"]?.claudeActivityText = nil
        $0.worktrees[id: "w1"]?.claudeActivityUpdatedAt = nil
    }
}

// MARK: - Non-offline transitions preserve activity

@Test(arguments: [ClaudeSessionState.idle, .blocked, .error])
func `non-offline transitions clear progressText but preserve activity`(nextState: ClaudeSessionState) async {
    let clock = TestClock()
    let store = makeStore(
        worktree: makeWorktree(
            claudeStatus: .working(tool: "Bash"),
            claudeStatusText: "klause-execute — running tests",
            claudeActivityText: "waiting on user feedback",
            claudeActivityUpdatedAt: fixedDate
        ),
        clock: clock
    )

    await store.send(.claudeStatusChanged(worktreeId: "w1", state: nextState)) {
        $0.worktrees[id: "w1"]?.claudeStatus = nextState
        $0.worktrees[id: "w1"]?.claudeStatusText = nil
        // claudeActivityText and claudeActivityUpdatedAt intentionally unchanged.
    }
}
