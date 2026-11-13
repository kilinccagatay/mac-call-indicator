import AppKit
import EventKit

@MainActor final class CalendarSettingsView: NSObject {
    private let settings = AgendaSettings()
    private let calendars = NSPopUpButton()
    private let enabled = NSButton(checkboxWithTitle: "Share workday agenda with Home Assistant", target: nil, action: nil)
    private let meeting = NSButton(checkboxWithTitle: "Include scheduled meetings in the meeting indicator", target: nil, action: nil)
    private let receiver = NSSecureTextField()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let access = NSButton(title: "Allow Calendar access…", target: nil, action: nil)
    private let connect = NSButton(title: "Connect agenda to Home Assistant…", target: nil, action: nil)
    private let authentication = HomeAssistantSignIn()
    private let save = NSButton(title: "Save calendar settings", target: nil, action: nil)
    func makeView() -> NSStackView {
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 14
        func label(_ text: String) { let view = NSTextField(wrappingLabelWithString: text); view.font = .systemFont(ofSize: 12); view.textColor = .secondaryLabelColor; body.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        label("Optional · macOS Calendar")
        label("Read one calendar already synced to this Mac. Apple requires Full Calendar Access for reading; this app never creates, edits or deletes events.")
        access.target = self; access.action = #selector(requestAccess); access.bezelStyle = .rounded; body.addArrangedSubview(access)
        body.addArrangedSubview(NSTextField(labelWithString: "Work calendar"))
        calendars.setAccessibilityLabel("Work calendar"); body.addArrangedSubview(calendars)
        enabled.state = settings.enabled ? .on : .off; meeting.state = settings.includeInMeeting ? .on : .off
        body.addArrangedSubview(enabled); body.addArrangedSubview(meeting)
        label("Weekends show Monday. Changes are checked on Calendar notifications and every minute. Only titles and start/end times leave this Mac. Attendees, notes, locations and links are excluded. A scheduled event can show Meeting even if you do not join. Real calls and manual timers remain independent.")
        connect.target = self; connect.action = #selector(connectAgenda); connect.bezelStyle = .rounded; body.addArrangedSubview(connect)
        body.addArrangedSubview(NSTextField(labelWithString: "Agenda receiver webhook (advanced)"))
        receiver.placeholderString = "Paste a dedicated Home Assistant agenda webhook URL"
        receiver.setAccessibilityLabel("Agenda receiver webhook"); body.addArrangedSubview(receiver)
        receiver.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        label("Separate from your existing call receiver. Stored in Keychain. Leave blank to keep its current value; never paste an access token here. Agenda expires after 90 seconds without updates.")
        save.target = self; save.action = #selector(saveSettings); save.bezelStyle = .rounded; body.addArrangedSubview(save)
        body.addArrangedSubview(notice); notice.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        reloadCalendars()
        return body
    }
    private func reloadCalendars() {
        calendars.removeAllItems(); calendars.addItem(withTitle: "Choose a calendar…")
        if CalendarAgenda.authorized {
            for calendar in CalendarAgenda.shared.store.calendars(for: .event).sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
                calendars.addItem(withTitle: calendar.title); calendars.lastItem?.representedObject = calendar.calendarIdentifier
                if calendar.calendarIdentifier == settings.calendarID { calendars.select(calendars.lastItem) }
            }
            notice.stringValue = "Calendar access allowed. Select only the calendar you want to share."
        } else { notice.stringValue = "Calendar access is not allowed. Nothing is read or shared." }
        calendars.isEnabled = CalendarAgenda.authorized; save.isEnabled = CalendarAgenda.authorized
        access.title = CalendarAgenda.authorized ? "Refresh calendars" : "Allow Calendar access…"
    }
    @objc private func requestAccess() {
        if CalendarAgenda.authorized { reloadCalendars(); return }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .denied || status == .restricted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!); return
        }
        let completion: @Sendable (Bool, Error?) -> Void = { [weak self] _, _ in Task { @MainActor in self?.reloadCalendars() } }
        if #available(macOS 14.0, *) { CalendarAgenda.shared.store.requestFullAccessToEvents(completion: completion) }
        else { CalendarAgenda.shared.store.requestAccess(to: .event, completion: completion) }
    }
    @objc private func connectAgenda() {
        connect.isEnabled = false
        notice.stringValue = "Connecting a separate agenda receiver…"
        Task { @MainActor in
            defer { connect.isEnabled = true }
            do {
                let base = ConnectionStore.shared.settings.server
                let url = try EndpointPolicy.validate(base.isEmpty ? EndpointPolicy.defaultServer : base, base: true)
                let client = HomeAssistantClient(server: url)
                if client.credential("access") == nil && client.credential("refresh") == nil {
                    authentication.window = connect.window
                    try await authentication.signIn(server: url)
                }
                var config = ConnectionSettings()
                let key = "calendarAgendaPairingID"
                config.deviceID = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
                UserDefaults.standard.set(config.deviceID, forKey: key)
                config.name = "Work calendar"; config.server = url.absoluteString
                _ = try await client.pair(config)
                guard let entity = UserDefaults.standard.string(forKey: "calendarAgendaEntity") else { throw ConnectionError.missingIntegration }
                notice.stringValue = "Connected. Agenda entity: " + entity + ". Save calendar settings to start sharing."
            } catch { notice.stringValue = error.localizedDescription }
        }
    }
    @objc private func saveSettings() {
        guard let id = calendars.selectedItem?.representedObject as? String else { notice.stringValue = "Choose a calendar first."; return }
        do {
            try settings.saveReceiver(receiver.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            settings.calendarID = id; settings.includeInMeeting = meeting.state == .on; settings.enabled = enabled.state == .on
            receiver.stringValue = ""; notice.stringValue = "Calendar settings saved. Only the selected calendar is shared."
        } catch { notice.stringValue = error.localizedDescription }
    }
}
