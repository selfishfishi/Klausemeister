import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

private let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let testUUID2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

private func makeError(
    id: UUID = testUUID,
    source: StatusBarFeature.Source = .sync,
    message: String = "boom",
    teamKey: String? = nil
) -> StatusBarFeature.StatusError {
    StatusBarFeature.StatusError(id: id, source: source, message: message, teamKey: teamKey)
}

@Test func `errorReported appends to errors`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    } withDependencies: {
        $0.uuid = .constant(testUUID)
    }

    await store.send(.errorReported(source: .sync, message: "boom")) {
        $0.errors = [makeError()]
    }
}

@Test func `errorClearedForSource clears all matching errors`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [
            makeError(id: testUUID, source: .sync, message: "a"),
            makeError(id: testUUID2, source: .sync, message: "b")
        ])
    ) {
        StatusBarFeature()
    }

    await store.send(.errorClearedForSource(.sync)) {
        $0.errors = []
    }
}

@Test func `errorClearedForSource ignores mismatched source`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [makeError(source: .sync)])
    ) {
        StatusBarFeature()
    }

    await store.send(.errorClearedForSource(.worktree))
}

@Test func `syncStateChanged mirrors isSyncing`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    }

    await store.send(.syncStateChanged(true)) {
        $0.isSyncing = true
    }
    await store.send(.syncStateChanged(false)) {
        $0.isSyncing = false
    }
}

@Test func `dismissTapped clears all errors`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [makeError()])
    ) {
        StatusBarFeature()
    }

    await store.send(.dismissTapped) {
        $0.errors = []
    }
}

@Test func `copyTapped copies detail text and ends after timer`() async {
    let copiedValue = LockIsolated<String?>(nil)
    let testClock = TestClock()

    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [makeError(message: "full error message")])
    ) {
        StatusBarFeature()
    } withDependencies: {
        $0.continuousClock = testClock
        $0.pasteboard.setString = { value in
            copiedValue.setValue(value)
        }
    }

    await store.send(.copyTapped) {
        $0.copiedConfirmationVisible = true
    }

    #expect(copiedValue.value == "full error message")

    await testClock.advance(by: StatusBarFeature.copyConfirmationDuration)
    await store.receive(\.copiedConfirmationTimerEnded) {
        $0.copiedConfirmationVisible = false
    }
}

@Test func `copyTapped with no errors is a no-op`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    }

    await store.send(.copyTapped)
}

@Test func `dismissTapped while copy confirmation in flight cancels timer`() async {
    let testClock = TestClock()
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [makeError(message: "boom")])
    ) {
        StatusBarFeature()
    } withDependencies: {
        $0.continuousClock = testClock
        $0.pasteboard.setString = { _ in }
    }

    await store.send(.copyTapped) {
        $0.copiedConfirmationVisible = true
    }
    await store.send(.dismissTapped) {
        $0.errors = []
        $0.copiedConfirmationVisible = false
    }
    await testClock.advance(by: StatusBarFeature.copyConfirmationDuration)
}

// MARK: - Per-Team Error Tests

@Test func `teamErrorsReported adds per-team sync errors`() async {
    var uuidCount = 0
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    } withDependencies: {
        $0.uuid = .init { uuidCount += 1; return UUID(uuidString: "00000000-0000-0000-0000-00000000000\(uuidCount)")! }
    }

    await store.send(.teamErrorsReported([
        .init(teamKey: "KLA", message: "rate limited"),
        .init(teamKey: "MOB", message: "network error")
    ])) {
        $0.errors = [
            makeError(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                source: .sync, message: "rate limited", teamKey: "KLA"
            ),
            makeError(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                source: .sync, message: "network error", teamKey: "MOB"
            )
        ]
    }
}

@Test func `teamErrorsReported replaces previous sync team errors`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [
            makeError(source: .sync, message: "old failure", teamKey: "KLA")
        ])
    ) {
        StatusBarFeature()
    } withDependencies: {
        $0.uuid = .constant(testUUID2)
    }

    await store.send(.teamErrorsReported([
        .init(teamKey: "MOB", message: "new failure")
    ])) {
        $0.errors = [
            makeError(id: testUUID2, source: .sync, message: "new failure", teamKey: "MOB")
        ]
    }
}

@Test func `summaryMessage for single error shows inline detail`() {
    let state = StatusBarFeature.State(errors: [
        makeError(source: .sync, message: "rate limited", teamKey: "KLA")
    ])
    #expect(state.summaryMessage == "KLA: rate limited")
}

@Test func `summaryMessage for multiple teams shows count and names`() {
    let state = StatusBarFeature.State(errors: [
        makeError(id: testUUID, source: .sync, message: "rate limited", teamKey: "KLA"),
        makeError(id: testUUID2, source: .sync, message: "timeout", teamKey: "MOB")
    ])
    #expect(state.summaryMessage == "Sync failed for 2 teams: KLA, MOB")
}

@Test func `summaryMessage for non-team error shows message directly`() {
    let state = StatusBarFeature.State(errors: [
        makeError(source: .meister, message: "DB save failed")
    ])
    #expect(state.summaryMessage == "DB save failed")
}

@Test func `detailText formats all errors with team keys`() {
    let state = StatusBarFeature.State(errors: [
        makeError(id: testUUID, source: .sync, message: "rate limited", teamKey: "KLA"),
        makeError(id: testUUID2, source: .meister, message: "DB save failed")
    ])
    #expect(state.detailText == "[KLA] rate limited\nDB save failed")
}

@Test func `dismissError removes single error from list`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(errors: [
            makeError(id: testUUID, source: .sync, message: "a"),
            makeError(id: testUUID2, source: .sync, message: "b")
        ])
    ) {
        StatusBarFeature()
    }

    await store.send(.dismissError(id: testUUID)) {
        $0.errors = [makeError(id: testUUID2, source: .sync, message: "b")]
    }
}

@Test func `errorDetailToggled toggles expansion state`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    }

    await store.send(.errorDetailToggled) {
        $0.isErrorDetailExpanded = true
    }
    await store.send(.errorDetailToggled) {
        $0.isErrorDetailExpanded = false
    }
}
