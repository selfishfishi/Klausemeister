import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

private let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private func makeError(source: StatusBarFeature.Source = .sync, message: String = "boom") -> StatusBarFeature.StatusError {
    StatusBarFeature.StatusError(id: testUUID, source: source, message: message)
}

@Test func `errorReported sets active error`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    } withDependencies: {
        $0.uuid = .constant(testUUID)
    }

    await store.send(.errorReported(source: .sync, message: "boom")) {
        $0.activeError = makeError()
    }
}

@Test func `errorClearedForSource clears matching error`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(activeError: makeError(source: .sync))
    ) {
        StatusBarFeature()
    }

    await store.send(.errorClearedForSource(.sync)) {
        $0.activeError = nil
    }
}

@Test func `errorClearedForSource ignores mismatched source`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(activeError: makeError(source: .sync))
    ) {
        StatusBarFeature()
    }

    // No state change expected — assertion is that the closure is absent.
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

@Test func `dismissTapped clears active error`() async {
    let store = TestStore(
        initialState: StatusBarFeature.State(activeError: makeError())
    ) {
        StatusBarFeature()
    }

    await store.send(.dismissTapped) {
        $0.activeError = nil
    }
}

@Test func `copyTapped invokes pasteboard and ends after timer`() async {
    let copiedValue = LockIsolated<String?>(nil)
    let testClock = TestClock()

    let store = TestStore(
        initialState: StatusBarFeature.State(activeError: makeError(message: "full error message"))
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

@Test func `copyTapped with no active error is a no-op`() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
        StatusBarFeature()
    }

    await store.send(.copyTapped)
}

@Test func `dismissTapped while copy confirmation in flight cancels timer and resets flag`() async {
    let testClock = TestClock()
    let store = TestStore(
        initialState: StatusBarFeature.State(activeError: makeError(message: "boom"))
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
        $0.activeError = nil
        $0.copiedConfirmationVisible = false
    }
    // Advancing the clock past the timer duration must NOT produce copiedConfirmationTimerEnded
    // because dismissTapped cancelled the in-flight effect.
    await testClock.advance(by: StatusBarFeature.copyConfirmationDuration)
}
