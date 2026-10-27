import AppKit
import ServiceManagement

final class LoginLaunch: NSObject, NSMenuDelegate {
    private let service = SMAppService.mainApp
    private let item = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")

    func add(to menu: NSMenu) {
        item.target = self
        item.action = #selector(toggle)
        menu.addItem(item)
        menu.delegate = self
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        switch service.status {
        case .enabled:
            item.state = .on
            item.title = "Start at Login"
        case .requiresApproval:
            item.state = .mixed
            item.title = "Start at Login (Approval Required)"
        default:
            item.state = .off
            item.title = "Start at Login"
        }
    }

    @objc private func toggle() {
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                // mainApp.unregister leaves the current app running.
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Change Login Startup"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }
}
