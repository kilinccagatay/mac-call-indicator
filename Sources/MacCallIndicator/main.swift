import AppKit
import ApplicationServices
import Foundation
import ServiceManagement

// Read-only AX queries. Never request AX actions or read a window's title.
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func inspectWindow(_ window: AXUIElement) -> Bool {
    var queue = [window]
    var index = 0
    var evidence = CallEvidence()
    while index < queue.count && index < 6000 {
        let element = queue[index]
        index += 1
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        // Skip editable fields: no chat drafts or typed input are read.
        if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) { continue }
        if role == kAXButtonRole || role == kAXCheckBoxRole {
            for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let value = attribute(element, key) as? String { evidence.inspectControl(value) }
            }
        } else if role == kAXStaticTextRole {
            for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let value = attribute(element, key) as? String { evidence.inspectTimer(value) }
            }
        }
        queue.append(contentsOf: children(element))
    }
    if CommandLine.arguments.contains("--diagnose") {
        print("end=\(evidence.endControl) mic=\(evidence.microphoneControl) timer=\(evidence.elapsedSeconds != nil) scanned=\(index) complete=\(index == queue.count)")
    }
    // An incomplete scan must not create a positive indicator.
    return index == queue.count && evidence.connected
}

func connectedCall() -> Bool {
    guard AXIsProcessTrusted() else { return false }
    // Teams is the initial validated target. Additional app profiles must pass
    // real connected/ringing/muted/ended tests before being enabled.
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams2") {
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows where inspectWindow(window) { return true }
    }
    return false
}

func webhookURL() -> URL? {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MacCallIndicator/webhook-url")
    guard let text = try? String(contentsOf: base, encoding: .utf8),
          let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          ["https", "http"].contains(url.scheme), url.user == nil, url.password == nil else { return nil }
    return url
}

func send(_ value: Bool, to url: URL) {
    var request = URLRequest(url: url, timeoutInterval: 4)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data((value ? "{\"in_call\":true}" : "{\"in_call\":false}").utf8)
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    let done = DispatchSemaphore(value: 0)
    session.dataTask(with: request) { _, _, _ in done.signal() }.resume()
    _ = done.wait(timeout: .now() + 5)
    session.invalidateAndCancel()
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

let arguments = Set(CommandLine.arguments.dropFirst())
// Used by installation/removal scripts; no Accessibility access is needed.
if arguments.contains("--login-status") {
    let status = SMAppService.mainApp.status
    print(status == .enabled ? "enabled" : status == .requiresApproval ? "requires-approval" : "disabled")
    exit(0)
}
if arguments.contains("--enable-login") || arguments.contains("--disable-login") {
    do {
        let service = SMAppService.mainApp
        if arguments.contains("--enable-login") {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
        print(service.status == .enabled ? "enabled" : service.status == .requiresApproval ? "requires-approval" : "disabled")
    } catch {
        fputs("Login setting could not be updated: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(0)
}
if arguments.contains("--request-access") {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    print("accessibility_authorized=\(AXIsProcessTrustedWithOptions(options))")
    exit(0)
}
if arguments.contains("--once") || arguments.contains("--diagnose") {
    let manual = ManualMeetingState()
    let now = Date()
    let value = ManualMeetingState.isMeeting(callDetected: connectedCall(), manualUntil: manual.deadline(now: now), now: now)
    print("{\"in_call\":\(value),\"observer_authorized\":\(AXIsProcessTrusted())}")
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "○"
statusItem.button?.toolTip = "Mac Call Indicator"
let menu = NSMenu()
let statusLine = NSMenuItem(title: "Checking Accessibility permission…", action: nil, keyEquivalent: "")
menu.addItem(statusLine)
menu.addItem(.separator())
let manualMeeting = ManualMeetingState()
let manualMenu = ManualMeetingMenu(state: manualMeeting)
manualMenu.add(to: menu)
menu.addItem(.separator())
let connectionMenu = MainActor.assumeIsolated {
    let controller = ConnectionSettingsMenu()
    controller.add(to: menu)
    return controller
}
menu.addItem(.separator())
let loginLaunch = LoginLaunch()
loginLaunch.add(to: menu)
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu
var lastValue: Bool? = nil
var lastSend = Date.distantPast
let meetingTest = TransientMeetingTest()
let pollQueue = DispatchQueue(label: "local.MacCallIndicator.poll")
let pollTimer = DispatchSource.makeTimerSource(queue: pollQueue)
pollTimer.schedule(deadline: .now(), repeating: 2)
func updateCallState() {
    let detected = autoreleasepool { connectedCall() }
    let authorized = AXIsProcessTrusted()
    let now = Date()
    let until = manualMeeting.deadline(now: now)
    let agenda = CalendarAgenda.shared.report(now: now)
    let scheduled = CalendarAgenda.shared.settings.includeInMeeting && agenda.scheduledMeeting
    let value = AgendaPolicy.meeting(call: detected, manual: until != nil || meetingTest.active(now: now), scheduled: scheduled)
    DispatchQueue.main.async {
        let minutes = until.map { ManualMeetingState.remainingMinutes(until: $0, now: Date()) }
        let title = minutes.map { "● \($0)m" } ?? (value ? "●" : "○")
        let attributed = NSMutableAttributedString(string: title)
        if value { attributed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: 1)) }
        statusItem.button?.attributedTitle = attributed
        if let minutes = minutes {
            statusLine.title = "Manual meeting · \(minutes) min remaining" +
                (authorized ? "" : " · Accessibility permission required — Open Settings…")
        } else {
            statusLine.title = scheduled ? "Scheduled meeting" : !authorized ? "Accessibility permission required — Open Settings…" : detected ? "Call active" : "No active call"
        }
        AccessibilityPermission.shared.configure(statusLine, authorized: authorized)
        connectionMenu.refreshPermissionNotice()
        manualMenu.refresh()
    }
    if value != lastValue || now.timeIntervalSince(lastSend) >= 10 {
        // Local diagnostics from the actual menu-bar process, rather than a
        // terminal child that may inherit a different Accessibility approval.
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacCallIndicator")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let statusURL = support.appendingPathComponent("status.json")
            let data = try JSONSerialization.data(withJSONObject: [
                "in_call": value, "observer_authorized": authorized
            ])
            try data.write(to: statusURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusURL.path)
        } catch { /* Diagnostics must not interrupt detection or leak paths. */ }
        // Without AX permission, silence is unknown rather than a verified idle
        // report. An explicit manual/test meeting is still valid evidence.
        if authorized || until != nil || scheduled || meetingTest.active(now: now),
           let endpoint = ConnectionStore.shared.endpoint() { send(value, to: endpoint) }
        // Boolean-only local logging. No labels, URLs, tokens, or call metadata.
        if value != lastValue {
            print("in_call=\(value) observer_authorized=\(AXIsProcessTrusted())")
            fflush(stdout)
        }
        if CalendarAgenda.shared.settings.enabled, let agendaURL = CalendarAgenda.shared.settings.receiver() {
            CalendarAgenda.shared.send(agenda, to: agendaURL)
        }
        lastSend = now
        lastValue = value
    }
}
manualMenu.onChange = { pollQueue.async { updateCallState() } }
MainActor.assumeIsolated {
    connectionMenu.onChange = { pollQueue.async { lastSend = .distantPast; updateCallState() } }
    connectionMenu.onTest = {
        meetingTest.start()
        pollQueue.async { lastSend = .distantPast; updateCallState() }
    }
}
pollTimer.setEventHandler { updateCallState() }
pollTimer.resume()
if arguments.contains("--settings") {
    DispatchQueue.main.async { connectionMenu.openSettings() }
}
application.run()
