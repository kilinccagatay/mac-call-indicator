import AppKit

final class ManualMeetingMenu: NSObject, NSWindowDelegate {
    private let state: ManualMeetingState
    private let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let endItem = NSMenuItem(title: "End manual meeting", action: nil, keyEquivalent: "")
    private var panel: NSPanel?
    private var picker: NSDatePicker?
    private var preview: NSTextField?
    var onChange: (() -> Void)?

    init(state: ManualMeetingState) { self.state = state }

    func add(to menu: NSMenu) {
        menu.addItem(summary)
        for (title, action) in [
            ("Meeting until…", #selector(chooseTime)),
            ("30 min meeting", #selector(thirtyMinutes)),
            ("1 hour meeting", #selector(oneHour))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        endItem.target = self
        endItem.action = #selector(endMeeting)
        menu.addItem(endItem)
        refresh()
    }

    func refresh(now: Date = Date()) {
        let until = state.deadline(now: now)
        summary.isHidden = until == nil
        endItem.isHidden = until == nil
        if let until = until {
            summary.title = "Until \(formatted(until)) · \(ManualMeetingState.remainingMinutes(until: until, now: now)) min left"
        }
        if panel?.isVisible == true { updatePreview() }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return f.string(from: date)
    }

    private func begin(minutes: Int) {
        let now = Date()
        state.start(until: now.addingTimeInterval(Double(minutes * 60)), now: now)
        refresh()
        onChange?()
    }

    @objc private func thirtyMinutes() { begin(minutes: 30) }
    @objc private func oneHour() { begin(minutes: 60) }
    @objc private func endMeeting() {
        state.cancel()
        refresh()
        onChange?()
    }

    @objc private func chooseTime() {
        if panel == nil { makePanel() }
        let now = Date()
        picker?.minDate = now
        picker?.dateValue = state.deadline(now: now) ??
            Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 + 30 * 60)
        updatePreview()
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func makePanel() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Meeting until"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -22)
        ])
        let heading = NSTextField(labelWithString: "Set a meeting end time")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        content.addArrangedSubview(heading)
        let detail = NSTextField(labelWithString: "Your indicator stays on until this time.")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 13)
        content.addArrangedSubview(detail)
        let datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.font = .systemFont(ofSize: 18)
        datePicker.target = self
        datePicker.action = #selector(updatePreview)
        datePicker.setAccessibilityLabel("Meeting end date and time")
        content.addArrangedSubview(datePicker)
        let remaining = NSTextField(labelWithString: "")
        remaining.font = .systemFont(ofSize: 13, weight: .medium)
        content.addArrangedSubview(remaining)
        let zone = NSTextField(labelWithString: "Local time · \(TimeZone.current.identifier)")
        zone.font = .systemFont(ofSize: 11)
        zone.textColor = .tertiaryLabelColor
        content.addArrangedSubview(zone)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fill
        buttons.addArrangedSubview(NSView())
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(closePicker))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let start = NSButton(title: "Start meeting", target: self, action: #selector(startChosenMeeting))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(start)
        content.addArrangedSubview(buttons)
        buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        panel = window
        picker = datePicker
        preview = remaining
    }

    @objc private func updatePreview() {
        guard let date = picker?.dateValue else { return }
        let now = Date()
        let valid = date > now
        preview?.stringValue = valid ? "\(ManualMeetingState.remainingMinutes(until: date, now: now)) minutes · ends \(formatted(date))" : "Choose a future end time."
        preview?.textColor = valid ? .secondaryLabelColor : .systemRed
    }

    @objc private func startChosenMeeting() {
        panel?.makeFirstResponder(nil)
        guard let date = picker?.dateValue, state.start(until: date) else {
            updatePreview()
            NSSound.beep()
            return
        }
        panel?.orderOut(nil)
        refresh()
        onChange?()
    }

    @objc private func closePicker() { panel?.orderOut(nil) }
}
