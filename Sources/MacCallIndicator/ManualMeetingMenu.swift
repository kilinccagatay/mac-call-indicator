import AppKit

final class ManualMeetingMenu: NSObject, NSTextFieldDelegate {
    private let state: ManualMeetingState
    private let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let endItem = NSMenuItem(title: "End manual meeting", action: nil, keyEquivalent: "")
    private var panel: NSPanel?
    private var hourField: NSTextField?
    private var minuteField: NSTextField?
    private var dial: MeetingClockDial?
    private var modeControl: NSSegmentedControl?
    private var preview: NSTextField?
    private var startButton: NSButton?
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
    @objc private func endMeeting() { state.cancel(); refresh(); onChange?() }

    @objc private func chooseTime() {
        if panel == nil { makePanel() }
        let now = Date()
        select(state.deadline(now: now) ?? Date(timeIntervalSince1970:
            floor(now.timeIntervalSince1970 / 60) * 60 + 30 * 60))
        setMode(minutes: false)
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func select(_ date: Date) {
        hourField?.stringValue = String(format: "%02d", Calendar.current.component(.hour, from: date))
        minuteField?.stringValue = String(format: "%02d", Calendar.current.component(.minute, from: date))
        updatePreview()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func fillWidth(_ view: NSView, in stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makePanel() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 440),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Meeting until"
        window.isReleasedWhenClosed = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -22)
        ])
        let timeRow = NSStackView()
        timeRow.orientation = .horizontal
        timeRow.alignment = .centerY
        timeRow.spacing = 12
        content.addArrangedSubview(timeRow)
        hourField = timePart(title: "Hour", maximum: 23, in: timeRow)
        timeRow.addArrangedSubview(label(":", size: 38, weight: .light, color: .tertiaryLabelColor))
        minuteField = timePart(title: "Minute", maximum: 59, in: timeRow)
        let mode = NSSegmentedControl(labels: ["Hour", "Minute"], trackingMode: .selectOne,
                                      target: self, action: #selector(changeMode))
        mode.selectedSegment = 0
        mode.setAccessibilityLabel("Clock selection")
        content.addArrangedSubview(mode)
        modeControl = mode
        let clock = MeetingClockDial(frame: .zero)
        clock.widthAnchor.constraint(equalToConstant: 224).isActive = true
        clock.heightAnchor.constraint(equalToConstant: 224).isActive = true
        clock.onPick = { [weak self] value, minutes in
            let field = minutes ? self?.minuteField : self?.hourField
            field?.stringValue = String(format: "%02d", value)
            self?.updatePreview()
        }
        clock.onFinishHour = { [weak self] in self?.setMode(minutes: true) }
        content.addArrangedSubview(clock)
        dial = clock
        let remaining = label("", size: 13, color: .secondaryLabelColor)
        content.addArrangedSubview(remaining)
        preview = remaining
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
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
        fillWidth(buttons, in: content)
        startButton = start
        panel = window
    }

    private func timePart(title: String, maximum: Int, in row: NSStackView) -> NSTextField {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 2
        let field = NSTextField(string: "00")
        field.font = .monospacedDigitSystemFont(ofSize: 36, weight: .medium)
        field.alignment = .center
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.delegate = self
        field.tag = maximum
        field.setAccessibilityLabel("End \(title.lowercased()), 24-hour time")
        field.toolTip = "Type \(title.lowercased()) or use the up and down arrow keys."
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        column.addArrangedSubview(field)
        row.addArrangedSubview(column)
        return field
    }

    private func setMode(minutes: Bool) {
        modeControl?.selectedSegment = minutes ? 1 : 0
        dial?.selectingMinutes = minutes
    }
    @objc private func changeMode(_ sender: NSSegmentedControl) { setMode(minutes: sender.selectedSegment == 1) }
    func controlTextDidBeginEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField { setMode(minutes: field === minuteField) }
    }

    func controlTextDidChange(_ notification: Notification) { updatePreview() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField,
              commandSelector == #selector(NSResponder.moveUp(_:)) || commandSelector == #selector(NSResponder.moveDown(_:)) else { return false }
        let delta = commandSelector == #selector(NSResponder.moveUp(_:)) ? 1 : -1
        let current = min(field.tag, max(0, Int(field.stringValue) ?? 0))
        field.stringValue = String(format: "%02d", (current + delta + field.tag + 1) % (field.tag + 1))
        field.selectText(nil)
        updatePreview()
        return true
    }
    private func chosenEnd(now: Date = Date()) -> Date? {
        guard let hour = Int(hourField?.stringValue ?? ""), let minute = Int(minuteField?.stringValue ?? "") else { return nil }
        return ManualMeetingTime.next(hour: hour, minute: minute, now: now)
    }

    private func updatePreview() {
        dial?.hour = Int(hourField?.stringValue ?? "") ?? 0
        dial?.minute = Int(minuteField?.stringValue ?? "") ?? 0
        let now = Date()
        guard let end = chosenEnd(now: now) else {
            preview?.stringValue = "Enter a time between 00:00 and 23:59"
            preview?.textColor = .systemRed
            startButton?.isEnabled = false
            return
        }
        preview?.stringValue = "\(ManualMeetingState.remainingMinutes(until: end, now: now)) min from now"
        preview?.textColor = .secondaryLabelColor
        startButton?.isEnabled = true
    }
    @objc private func startChosenMeeting() {
        updatePreview()
        guard startButton?.isEnabled == true else { NSSound.beep(); return }
        guard let end = chosenEnd(),
              state.start(until: end) else { updatePreview(); NSSound.beep(); return }
        panel?.orderOut(nil)
        refresh()
        onChange?()
    }
    @objc private func closePicker() { panel?.orderOut(nil) }
}
