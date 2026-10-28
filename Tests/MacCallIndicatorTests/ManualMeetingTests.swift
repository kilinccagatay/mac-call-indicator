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

    func testTimeOnlyPickerUsesNextOccurrenceAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 23, minute: 45))!
        let end = ManualMeetingTime.next(hour: 0, minute: 15, now: now, calendar: calendar)!
        XCTAssertEqual(end.timeIntervalSince(now), 1800)
        XCTAssertNil(ManualMeetingTime.next(hour: 24, minute: 0, now: now, calendar: calendar))
        XCTAssertNil(ManualMeetingTime.next(hour: 12, minute: 60, now: now, calendar: calendar))
    }

    func testClockDialHitTestingUses24HourRingsAndMinuteAngles() {
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 112, y: 22), diameter: 224, minutes: false), 12)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 112, y: 54), diameter: 224, minutes: false), 0)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 202, y: 112), diameter: 224, minutes: false), 3)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 170, y: 112), diameter: 224, minutes: false), 15)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 112, y: 202), diameter: 224, minutes: true), 30)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 22, y: 112), diameter: 224, minutes: true), 45)
        XCTAssertEqual(MeetingClockDial.value(at: NSPoint(x: 112, y: 22), diameter: 224, minutes: true), 0)
        XCTAssertNil(MeetingClockDial.value(at: NSPoint(x: 112, y: 112), diameter: 224, minutes: false))
    }
}
