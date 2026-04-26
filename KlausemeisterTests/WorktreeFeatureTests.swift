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
    meisterActivityUpdatedAt: Date? = nil
) -> Worktree {
    var worktree = Worktree(
        id: id,
        name: "Alpha",
        sortOrder: 0,
        gitWorktreePath: "/tmp/\(id)"
    )
    worktree.meisterSessionState = meisterSessionState
    worktree.meisterStatusText = meisterStatusText
    worktree.meisterActivityText = meisterActivityText
    worktree.meisterActivityUpdatedAt = meisterActivityUpdatedAt
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

    // TTL effect clears the slot once 30s elapse on the injected clock.
    await clock.advance(by: .seconds(31))
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

// MARK: - Non-offline transitions preserve activity

@Test(arguments: [MeisterSessionState.idle, .blocked, .error])
func `non-offline transitions clear progressText but preserve activity`(nextState: MeisterSessionState) async {
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
        $0.worktrees[id: "w1"]?.meisterStatusText = nil
        // meisterActivityText and meisterActivityUpdatedAt intentionally unchanged.
    }
}
