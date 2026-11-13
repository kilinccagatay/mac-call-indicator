import AppKit
import CoreGraphics

/// Boolean-only computer availability; independent of call and calendar access.
struct ComputerActivityState: Equatable {
    var locked = false
    var displayAsleep = false
    var systemAsleep = false
    var sessionActive = true
    var active: Bool { !locked && !displayAsleep && !systemAsleep && sessionActive }
}

public final class ComputerActivity {
    private let lock = NSLock()
    private var state = ComputerActivityState()
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    public var onChange: (() -> Void)?
    public var active: Bool { lock.lock(); defer { lock.unlock() }; return state.active }

    public init() {
        // Snapshot only booleans; never retain session names or identifiers.
        state.displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            state.locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            state.sessionActive = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        // macOS lock notifications supplement public display/session events.
        // No AX inspection, input monitoring, or screen capture is involved.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         update: @escaping (inout ComputerActivityState) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            let previous = self.state
            update(&self.state)
            let changed = previous != self.state
            self.lock.unlock()
            if changed { self.onChange?() }
        }
        observations.append((center, token))
    }
    deinit { for (center, token) in observations { center.removeObserver(token) } }
}
