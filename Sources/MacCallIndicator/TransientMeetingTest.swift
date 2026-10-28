import Foundation

/// Testing the receiver must never overwrite the user's manual deadline.
final class TransientMeetingTest {
    private let lock = NSLock()
    private var until = Date.distantPast
    func start(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        until = now.addingTimeInterval(10)
    }
    func active(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return now < until
    }
}
