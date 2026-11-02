import XCTest
@testable import MacCallIndicator

final class ComputerActivityTests: XCTestCase {
    func testUnlockDoesNotOverrideSleepingDisplayAndWakeDoesNotUnlock() {
        var state = ComputerActivityState()
        XCTAssertTrue(state.active)
        state.locked = true; state.displayAsleep = true
        state.displayAsleep = false
        XCTAssertFalse(state.active)
        state.locked = false
        XCTAssertTrue(state.active)
        state.systemAsleep = true
        state.locked = true; state.locked = false
        XCTAssertFalse(state.active)
        state.systemAsleep = false
        XCTAssertTrue(state.active)
    }
    func testFastUserSwitchStaysInactiveUntilSessionAndDisplayReturn() {
        var state = ComputerActivityState()
        state.sessionActive = false
        state.displayAsleep = true
        state.sessionActive = true
        XCTAssertFalse(state.active)
        state.displayAsleep = false
        XCTAssertTrue(state.active)
    }
}
