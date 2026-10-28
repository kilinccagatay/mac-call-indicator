import Foundation

/// A manual deadline is independent of call events. Wall-clock time is the
/// source of truth, so sleep, restarts, and local clock changes do not drift it.
final class ManualMeetingState {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "manualMeetingEndEpoch"
    private var end: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let epoch = defaults.double(forKey: key)
        end = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    @discardableResult
    func start(until date: Date, now: Date = Date()) -> Bool {
        guard date > now else { return false }
        lock.lock()
        defer { lock.unlock() }
        end = date
        defaults.set(date.timeIntervalSince1970, forKey: key)
        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        end = nil
        defaults.removeObject(forKey: key)
    }

    func deadline(now: Date = Date()) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        guard let date = end else { return nil }
        if date <= now {
            end = nil
            defaults.removeObject(forKey: key)
            return nil
        }
        return date
    }

    static func remainingMinutes(until date: Date, now: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
    }

    static func isMeeting(callDetected: Bool, manualUntil: Date?, now: Date) -> Bool {
        callDetected || (manualUntil.map { $0 > now } ?? false)
    }
}
