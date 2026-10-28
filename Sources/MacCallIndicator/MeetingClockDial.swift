import AppKit

/// Local, dependency-free clock input. Dragging is optional: a click, the arrow
/// keys, or the editable time fields can make the same selection.
final class MeetingClockDial: NSView {
    var selectingMinutes = false { didSet { updateAccessibility(); needsDisplay = true } }
    var hour = 0 { didSet { updateAccessibility(); needsDisplay = true } }
    var minute = 0 { didSet { updateAccessibility(); needsDisplay = true } }
    var onPick: ((Int, Bool) -> Void)?
    var onFinishHour: (() -> Void)?
    private var pickedHour = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateAccessibility() {
        setAccessibilityLabel(selectingMinutes ? "End minute" : "End hour, 24-hour clock")
        setAccessibilityValue(NSNumber(value: selectingMinutes ? minute : hour))
        setAccessibilityHelp("Click or drag to choose. Use arrow keys to adjust.")
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let outer = bounds.width / 2 - 22
        let inner = outer * 0.65
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
        let value = selectingMinutes ? minute : hour % 12
        let radius = !selectingMinutes && (hour == 0 || hour > 12) ? inner : outer
        let angle = Double(value) / (selectingMinutes ? 60 : 12) * .pi * 2 - .pi / 2
        let tip = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        NSColor.controlAccentColor.setStroke()
        let hand = NSBezierPath()
        hand.move(to: center)
        hand.line(to: tip)
        hand.lineWidth = 2
        hand.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - 16, y: tip.y - 16, width: 32, height: 32)).fill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)).fill()
        for ring in 0..<(selectingMinutes ? 1 : 2) {
            for index in 0..<12 {
                let number = selectingMinutes ? index * 5 : (ring == 0 ? (index == 0 ? 12 : index) : (index == 0 ? 0 : index + 12))
                let selected = number == (selectingMinutes ? minute : hour)
                let text = selectingMinutes || number == 0 ? String(format: "%02d", number) : String(number)
                let angle = Double(index) / 12 * .pi * 2 - .pi / 2
                let r = ring == 0 ? outer : inner
                let position = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if selectingMinutes && !selected && hypot(position.x - tip.x, position.y - tip.y) < 26 { continue }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: ring == 0 ? 14 : 12, weight: selected ? .semibold : .regular),
                    .foregroundColor: selected ? NSColor.white : NSColor.labelColor.withAlphaComponent(ring == 0 ? 1 : 0.72)
                ]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: position.x - size.width / 2,
                                                   y: position.y - size.height / 2), withAttributes: attributes)
            }
        }
        if selectingMinutes && minute % 5 != 0 {
            let text = String(format: "%02d", minute) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: tip.x - size.width / 2, y: tip.y - size.height / 2), withAttributes: attributes)
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    @discardableResult private func pick(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard let value = Self.value(at: point, diameter: bounds.width, minutes: selectingMinutes) else { return false }
        onPick?(value, selectingMinutes)
        return true
    }

    static func value(at point: NSPoint, diameter: CGFloat, minutes: Bool) -> Int? {
        let dx = point.x - diameter / 2, dy = point.y - diameter / 2
        guard hypot(dx, dy) > 12 else { return nil }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += .pi * 2 }
        if minutes {
            return Int((angle / (.pi * 2) * 60).rounded()) % 60
        } else {
            let index = Int((angle / (.pi * 2) * 12).rounded()) % 12
            let inner = hypot(dx, dy) < (diameter / 2 - 22) * 0.825
            return inner ? (index == 0 ? 0 : index + 12) : (index == 0 ? 12 : index)
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let picked = pick(event)
        pickedHour = picked && !selectingMinutes
    }
    override func mouseDragged(with event: NSEvent) { pick(event) }
    override func mouseUp(with event: NSEvent) { if pickedHour { onFinishHour?() }; pickedHour = false }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) {
            let delta = [124, 126].contains(event.keyCode) ? 1 : -1
            let maximum = selectingMinutes ? 60 : 24
            onPick?(((selectingMinutes ? minute : hour) + delta + maximum) % maximum, selectingMinutes)
        } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformIncrement() -> Bool {
        onPick?(((selectingMinutes ? minute : hour) + 1) % (selectingMinutes ? 60 : 24), selectingMinutes)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        let count = selectingMinutes ? 60 : 24
        onPick?(((selectingMinutes ? minute : hour) - 1 + count) % count, selectingMinutes)
        return true
    }
}
