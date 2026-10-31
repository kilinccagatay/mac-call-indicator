import Foundation
import EventKit

// Deliberately excludes event identifiers, attendees, notes, locations and URLs.
struct AgendaItem: Codable, Equatable {
    let title: String
    let start: TimeInterval
    let end: TimeInterval
    func active(at now: Date) -> Bool { start <= now.timeIntervalSince1970 && now.timeIntervalSince1970 < end }
}
struct AgendaReport: Codable {
    let available: Bool
    let generated_at: TimeInterval
    let valid_until: TimeInterval
    let day_start: TimeInterval
    let day_end: TimeInterval
    let events: [AgendaItem]
    var scheduledMeeting: Bool { available && events.contains { $0.active(at: Date(timeIntervalSince1970: generated_at)) } }
}
enum AgendaPolicy {
    static func workday(now: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: now)
        while [1, 7].contains(calendar.component(.weekday, from: day)) { day = calendar.date(byAdding: .day, value: 1, to: day)! }
        return day
    }
    static func report(items: [AgendaItem], available: Bool, now: Date, calendar: Calendar = .current) -> AgendaReport {
        let start = workday(now: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let events = available ? items.filter {
            $0.start.isFinite && $0.end.isFinite && $0.start < $0.end &&
            $0.start < end.timeIntervalSince1970 && $0.end > max(start.timeIntervalSince1970, now.timeIntervalSince1970)
        }.sorted { $0.start < $1.start }.prefix(64).map {
            AgendaItem(title: String($0.title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(160)), start: $0.start, end: $0.end)
        } : []
        return AgendaReport(available: available, generated_at: now.timeIntervalSince1970,
                            valid_until: now.addingTimeInterval(90).timeIntervalSince1970, day_start: start.timeIntervalSince1970, day_end: end.timeIntervalSince1970, events: Array(events))
    }
    static func meeting(call: Bool, manual: Bool, scheduled: Bool) -> Bool { call || manual || scheduled }
}

struct AgendaSettings {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var enabled: Bool { get { defaults.bool(forKey: "calendarAgendaEnabled") } nonmutating set { defaults.set(newValue, forKey: "calendarAgendaEnabled") } }
    var includeInMeeting: Bool { get { defaults.bool(forKey: "calendarAgendaMeeting") } nonmutating set { defaults.set(newValue, forKey: "calendarAgendaMeeting") } }
    var calendarID: String { get { defaults.string(forKey: "calendarAgendaID") ?? "" } nonmutating set { defaults.set(newValue, forKey: "calendarAgendaID") } }
    func receiver() -> URL? {
        guard let value = CredentialStore.read("agenda-receiver"), let url = try? EndpointPolicy.validate(value), url.path.hasPrefix("/api/webhook/") else { return nil }
        return url
    }
    func saveReceiver(_ text: String) throws {
        if text.isEmpty { return }
        let url = try EndpointPolicy.validate(text)
        guard url.path.hasPrefix("/api/webhook/"), url.path.count > 13 else { throw ConnectionError.invalidSecret }
        try CredentialStore.write(url.absoluteString, account: "agenda-receiver")
    }
}

final class CalendarAgenda {
    static let shared = CalendarAgenda()
    let store = EKEventStore()
    let settings = AgendaSettings()
    private var cached: [AgendaItem] = []
    private var refreshed = Date.distantPast
    private var selectedID = ""
    private var cachedDay = Date.distantPast
    private let dirtyLock = NSLock()
    private var dirty = true
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.dirtyLock.lock(); self.dirty = true; self.dirtyLock.unlock()
        }
    }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
    // Called only from the existing serial poll queue. No event data is persisted.
    static var authorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    func report(now: Date) -> AgendaReport {
        guard settings.enabled, Self.authorized, !settings.calendarID.isEmpty,
              let calendar = store.calendar(withIdentifier: settings.calendarID) else {
            cached = []; refreshed = .distantPast
            return AgendaPolicy.report(items: [], available: false, now: now)
        }
        dirtyLock.lock(); let changed = dirty; dirty = false; dirtyLock.unlock()
        // EventKit changes arrive promptly after local synchronization. A minute
        // fallback also covers missed notifications, sleep and clock changes.
        if changed || cachedDay != AgendaPolicy.workday(now: now) || now.timeIntervalSince(refreshed) >= 60 || now < refreshed || selectedID != settings.calendarID {
            let day = AgendaPolicy.workday(now: now)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            let predicate = store.predicateForEvents(withStart: day, end: tomorrow, calendars: [calendar])
            cached = store.events(matching: predicate).filter { event in
                !event.isAllDay && event.status != .canceled && event.availability != .free &&
                event.startDate != nil && event.endDate != nil &&
                !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
            }.map { AgendaItem(title: $0.title ?? "Meeting", start: $0.startDate.timeIntervalSince1970, end: $0.endDate.timeIntervalSince1970) }
            refreshed = now; selectedID = settings.calendarID; cachedDay = day
        }
        return AgendaPolicy.report(items: cached, available: true, now: now)
    }
    func send(_ report: AgendaReport, to url: URL) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 5); session.invalidateAndCancel()
    }
}
