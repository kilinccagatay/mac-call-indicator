import XCTest
@testable import MacCallIndicator

final class HomeAssistantConnectionTests: XCTestCase {
    func testEndpointPolicyRejectsCredentialLeaksAndPublicPlainHTTP() throws {
        XCTAssertEqual(try EndpointPolicy.validate(EndpointPolicy.defaultServer, base: true).absoluteString,
                       "http://homeassistant.local:8123/")
        for value in ["http://example.com", "HTTP://example.com", "http://10.1.evil.2.3",
                      "https://user:password@example.com", "https://example.com?token=secret",
                      "https://example.com#secret", "file:///tmp/token"] {
            XCTAssertThrowsError(try EndpointPolicy.validate(value), value)
        }
        for value in ["http://192.168.1.2:8123", "http://172.16.1.1", "http://10.2.3.4",
                      "http://homeassistant.local:8123", "https://example.com", "http://[::1]:8123"] {
            XCTAssertNoThrow(try EndpointPolicy.validate(value), value)
        }
        XCTAssertThrowsError(try EndpointPolicy.validate("https://example.com/path", base: true))
    }

    func testOutputTypesNeverTreatReadOnlyEntityAsActuator() throws {
        XCTAssertNoThrow(try OutputMode.statusOnly.validate(target: ""))
        XCTAssertNoThrow(try OutputMode.lightColor.validate(target: "light.meeting_lamp"))
        XCTAssertNoThrow(try OutputMode.smartSwitch.validate(target: "switch.desk"))
        XCTAssertNoThrow(try OutputMode.inputBoolean.validate(target: "input_boolean.meeting"))
        for target in ["person.owner", "binary_sensor.meeting", "sensor.status", "switch.desk",
                       "light.", "light.a/b", "light.a\n"] {
            XCTAssertThrowsError(try OutputMode.lightOnOff.validate(target: target))
        }
        var config = ConnectionSettings()
        config.output = .statusOnly
        config.target = "light.should_not_be_controlled"
        XCTAssertEqual(config.pairingBody["target_entity"] as? String, "")
    }

    func testPKCEUsesRFC7636VectorAndRejectsForgedCallbacks() throws {
        XCTAssertEqual(OAuthPKCE.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let valid = URL(string: "mac-call-indicator://auth?code=code&state=expected")!
        XCTAssertEqual(try OAuthPKCE.code(from: valid, expectedState: "expected"), "code")
        for url in ["mac-call-indicator://auth?code=code&state=wrong",
                    "https://auth?code=code&state=expected",
                    "mac-call-indicator://evil?code=code&state=expected",
                    "mac-call-indicator://auth?code=a&code=b&state=expected"] {
            XCTAssertThrowsError(try OAuthPKCE.code(from: URL(string: url)!, expectedState: "expected"))
        }
    }

    func testReceiverTestExpiresWithoutChangingManualHour() {
        let now = Date(timeIntervalSince1970: 10000)
        let suite = "ConnectionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manual = ManualMeetingState(defaults: defaults)
        manual.start(until: now.addingTimeInterval(3600), now: now)
        let test = TransientMeetingTest()
        test.start(now: now)
        XCTAssertTrue(test.active(now: now.addingTimeInterval(9)))
        XCTAssertFalse(test.active(now: now.addingTimeInterval(10)))
        XCTAssertEqual(manual.deadline(now: now), now.addingTimeInterval(3600))
    }
}
