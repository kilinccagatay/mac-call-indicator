import XCTest
@testable import MacCallIndicator
final class CalendarAgendaTests: XCTestCase {
    func testBoundsAndPrivacyAndExpiry() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        let items = [AgendaItem(title: "Synthetic meeting\nExample", start: now.timeIntervalSince1970 - 10, end: now.timeIntervalSince1970 + 60),
                     AgendaItem(title: "Ended", start: 10, end: 20),
                     AgendaItem(title: "Invalid", start: .infinity, end: .infinity)]
        let report = AgendaPolicy.report(items: items, available: true, now: now)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertEqual(report.events.first?.title, "Synthetic meeting Example")
        XCTAssertTrue(report.scheduledMeeting)
        XCTAssertEqual(report.valid_until, now.timeIntervalSince1970 + 90)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), Set(["available", "generated_at", "valid_until", "day_start", "day_end", "events"]))
        let event = (json["events"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(event.keys), Set(["title", "start", "end"]))
        XCTAssertTrue(AgendaPolicy.report(items: items, available: false, now: now).events.isEmpty)
    }
    func testWeekendShowsMondayButCannotSetMeetingActive() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let saturday = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        let monday = AgendaPolicy.workday(now: saturday, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: monday), 2)
        let report = AgendaPolicy.report(items: [AgendaItem(title: "Monday example", start: monday.timeIntervalSince1970 + 36000, end: monday.timeIntervalSince1970 + 39600)], available: true, now: saturday, calendar: cal)
        XCTAssertEqual(report.events.count, 1); XCTAssertFalse(report.scheduledMeeting)
    }
    func testHalfOpenIntervalsAndIndependentSources() {
        let item = AgendaItem(title: "Synthetic", start: 100, end: 200)
        XCTAssertFalse(item.active(at: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(item.active(at: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(item.active(at: Date(timeIntervalSince1970: 200)))
        for call in [true, false] {
            XCTAssertTrue(AgendaPolicy.meeting(call: call, manual: true, scheduled: false))
            XCTAssertTrue(AgendaPolicy.meeting(call: call, manual: false, scheduled: true))
        }
        XCTAssertTrue(AgendaPolicy.meeting(call: true, manual: false, scheduled: false))
        XCTAssertFalse(AgendaPolicy.meeting(call: false, manual: false, scheduled: false))
    }
    func testLocalDayDSTAndMidnightExpiry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 59, second: 45))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let report = AgendaPolicy.report(items: [AgendaItem(title: "Tomorrow", start: tomorrow.timeIntervalSince1970, end: tomorrow.timeIntervalSince1970 + 100)], available: true, now: now, calendar: calendar)
        XCTAssertTrue(report.events.isEmpty)
        XCTAssertEqual(report.valid_until, now.timeIntervalSince1970 + 90)
    }
}
