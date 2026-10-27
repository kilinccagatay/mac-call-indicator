import XCTest
@testable import MacCallIndicator

final class CallEvidenceTests: XCTestCase {
    func testBusyOrMicrophoneAloneDoesNotTrigger() {
        var value = CallEvidence()
        value.inspectControl("Busy")
        value.inspectControl("Mute mic")
        XCTAssertFalse(value.connected)
    }
    func testConnectedAndMutedCalls() {
        for mic in ["Mute mic", "Unmute mic"] {
            var value = CallEvidence()
            value.inspectControl("Leave")
            value.inspectControl(mic)
            value.inspectTimer("00:14")
            XCTAssertTrue(value.connected)
        }
    }
    func testPrejoinAndRingingAreRejected() {
        var value = CallEvidence(endControl: true, microphoneControl: true, elapsedSeconds: 15)
        value.inspectControl("Join now")
        XCTAssertFalse(value.connected)
        value = CallEvidence(endControl: true, microphoneControl: true, elapsedSeconds: 0)
        XCTAssertFalse(value.connected)
    }
    func testNamesAndPhoneNumbersAreNotTimers() {
        for text in ["Meeting name", "+123456789", "00:99", "10:99:02", "Call duration 12:30"] {
            var value = CallEvidence(endControl: true, microphoneControl: true)
            value.inspectTimer(text)
            XCTAssertFalse(value.connected)
        }
    }
    func testEndedWindowHasNoPositiveEvidence() {
        XCTAssertFalse(CallEvidence().connected)
    }
}
