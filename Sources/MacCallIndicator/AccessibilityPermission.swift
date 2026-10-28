import AppKit
import ApplicationServices

/// Request/open the normal macOS permission UI only after an explicit click.
/// This never changes TCC settings or grants permission on the user's behalf.
final class AccessibilityPermission: NSObject {
    static let shared = AccessibilityPermission()
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let instructions = "Enable MacCallIndicator in Accessibility. If it is already enabled after an update, remove the old entry and add the installed app again. Restart MacCallIndicator if macOS requests it. No camera, microphone or screen-recording permission is needed."

    @objc func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !NSWorkspace.shared.open(Self.settingsURL) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func configure(_ item: NSMenuItem, authorized: Bool) {
        item.target = self
        item.action = authorized ? nil : #selector(openSettings)
        item.toolTip = authorized ? nil : Self.instructions
    }
}
