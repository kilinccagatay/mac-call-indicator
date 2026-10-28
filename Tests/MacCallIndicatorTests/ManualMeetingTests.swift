import XCTest
@testable import MacCallIndicator

final class ManualMeetingTests: XCTestCase {
    private func withState(_ test: (ManualMeetingState, UserDefaults) -> Void) {
        let suite = "ManualMeetingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(ManualMeetingState(defaults: defaults), defaults)
    }

    func testCallEndingDoesNotCancelOrExtendManualHour() {
        withState { state, _ in
            let now = Date(timeIntervalSince1970: 10000)
            let end = now.addingTimeInterval(3600)
            XCTAssertTrue(state.start(until: end, now: now))
            for call in [false, true, false, true, false] {
                XCTAssertTrue(ManualMeetingState.isMeeting(callDetected: call, manualUntil: state.deadline(now: now), now: now))
                XCTAssertEqual(state.deadline(now: now), end)
            }
            XCTAssertEqual(ManualMeetingState.remainingMinutes(until: end, now: now.addingTimeInterval(600)), 50)
        }
    }

    func testExpirationUsesClockAndKeepsRealCall() {
        withState { state, _ in
            let now = Date(timeIntervalSince1970: 10000)
            let end = now.addingTimeInterval(60)
            state.start(until: end, now: now)
            XCTAssertNotNil(state.deadline(now: end.addingTimeInterval(-1)))
            XCTAssertNil(state.deadline(now: end))
            XCTAssertFalse(ManualMeetingState.isMeeting(callDetected: false, manualUntil: state.deadline(now: end), now: end))
            XCTAssertTrue(ManualMeetingState.isMeeting(callDetected: true, manualUntil: state.deadline(now: end), now: end))
        }
    }

    func testPersistenceAndManualCancel() {
        withState { state, defaults in
            let now = Date(timeIntervalSince1970: 10000)
            let end = now.addingTimeInterval(1800)
            state.start(until: end, now: now)
            let restored = ManualMeetingState(defaults: defaults)
            XCTAssertEqual(restored.deadline(now: now), end)
            restored.cancel()
            XCTAssertNil(restored.deadline(now: now))
            XCTAssertNil(ManualMeetingState(defaults: defaults).deadline(now: now))
            XCTAssertTrue(ManualMeetingState.isMeeting(callDetected: true, manualUntil: nil, now: now))
        }
    }

    func testRejectsPastTimeAndRoundsRemainingMinutesUp() {
        withState { state, _ in
            let now = Date(timeIntervalSince1970: 10000)
            XCTAssertFalse(state.start(until: now, now: now))
            XCTAssertFalse(state.start(until: now.addingTimeInterval(-1), now: now))
            XCTAssertEqual(ManualMeetingState.remainingMinutes(until: now.addingTimeInterval(61), now: now), 2)
            XCTAssertEqual(ManualMeetingState.remainingMinutes(until: now.addingTimeInterval(1), now: now), 1)
            XCTAssertEqual(ManualMeetingState.remainingMinutes(until: now.addingTimeInterval(-1), now: now), 0)
        }
    }
}
