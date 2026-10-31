import AppKit
import ApplicationServices

@MainActor final class ConnectionSettingsMenu: NSObject {
    private let store = ConnectionStore.shared
    private var config = ConnectionStore.shared.settings
    private var window: NSWindow?
    private let server = NSTextField()
    private let useDefault = NSButton(title: "Use default", target: nil, action: nil)
    private let importButton = NSButton(title: "Import connection…", target: nil, action: nil)
    private let deviceName = NSTextField()
    private let transport = NSPopUpButton()
    private let secret = NSSecureTextField()
    private let secretLabel = NSTextField(labelWithString: "")
    private let profile = NSPopUpButton()
    private let target = NSComboBox()
    private let busyColor = NSColorWell()
    private let idleColor = NSColorWell()
    private let brightness = NSSlider(value: 60, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let brightnessValue = NSTextField(labelWithString: "60%")
    private var targetGroup: NSView?
    private var colorGroups: [NSView] = []
    private var offlineGroup: NSView?
    private var permissionNotice: NSView?
    private let idleOff = NSButton(checkboxWithTitle: "Turn off when idle instead of using idle color", target: nil, action: nil)
    private let offline = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let source = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save connection", target: nil, action: nil)
    private let reload = NSButton(title: "Load entities", target: nil, action: nil)
    private let signIn = NSButton(title: "Sign in with Home Assistant…", target: nil, action: nil)
    private let test = NSButton(title: "Test connection", target: nil, action: nil)
    private let sendTest = NSButton(title: "Test meeting for 10 seconds", target: nil, action: nil)
    private let disconnect = NSButton(title: "Disconnect", target: nil, action: nil)
    private let authentication = HomeAssistantSignIn()
    private let calendarSettings = CalendarSettingsView()
    private var working = false
    var onChange: (() -> Void)?
    var onTest: (() -> Void)?

    func add(to menu: NSMenu) {
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self
        menu.addItem(item)
    }

    @objc func openSettings() {
        if window == nil { makeWindow() }
        status.stringValue = store.configured ? (config.enabled ? "Connection configured. Tests never expose credentials." : "Disconnected.") : "Existing webhook connection is preserved until you save."
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updateControls()
    }

    private func text(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }
    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let row = NSStackView(views: [label, control])
        row.orientation = .vertical; row.alignment = .leading; row.spacing = 5
        control.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        if let control = control as? NSControl { control.setAccessibilityLabel(title) }
        return row
    }
    private func stack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        return stack
    }
    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func button(_ button: NSButton, action: Selector) {
        button.bezelStyle = .rounded; button.target = self; button.action = action
    }

    private func makeWindow() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Mac Call Indicator Settings"; win.isReleasedWhenClosed = false
        window = win; authentication.window = win
        let content = stack(); content.spacing = 16; content.translatesAutoresizingMaskIntoConstraints = false
        win.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: win.contentView!.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor, constant: -20)
        ])
        let tabs = NSTabView()
        tabs.heightAnchor.constraint(equalToConstant: 460).isActive = true
        for (title, body) in [("Connection", connectionView()), ("Output", outputView()), ("Calendar", calendarSettings.makeView())] {
            let item = NSTabViewItem(identifier: title); item.label = title
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let container = SettingsDocumentView()
            container.translatesAutoresizingMaskIntoConstraints = false
            body.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(body)
            scroll.documentView = container
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
                body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
                body.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
                body.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
            ])
            item.view = scroll; tabs.addTabViewItem(item)
        }
        add(tabs, to: content)
        source.font = .systemFont(ofSize: 11)
        source.stringValue = config.sourceEntity.isEmpty ? "Meeting entity: configured by your existing receiver." : "Meeting entity: " + config.sourceEntity
        add(source, to: content)
        status.font = .systemFont(ofSize: 12)
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        add(status, to: content)
        button(save, action: #selector(saveConnection))
        button(sendTest, action: #selector(testMeeting))
        button(disconnect, action: #selector(disconnectConnection))
        let actions = NSStackView(views: [disconnect, sendTest, NSView(), save])
        actions.spacing = 8
        add(actions, to: content)
        updateControls()
    }

    private func connectionView() -> NSStackView {
        let body = stack()
        let notice = stack()
        notice.spacing = 8
        let permissionButton = NSButton(title: "Open Accessibility Settings…",
            target: AccessibilityPermission.shared, action: #selector(AccessibilityPermission.openSettings))
        permissionButton.bezelStyle = .rounded
        add(text("Automatic Teams detection needs Accessibility permission. " + AccessibilityPermission.instructions), to: notice)
        notice.addArrangedSubview(permissionButton)
        add(notice, to: body)
        permissionNotice = notice
        if config.server.isEmpty, let old = store.endpoint(), var parts = URLComponents(url: old, resolvingAgainstBaseURL: false) {
            parts.path = ""; config.server = parts.url?.absoluteString ?? ""
        }
        server.stringValue = config.server
        server.placeholderString = EndpointPolicy.defaultServer
        deviceName.stringValue = config.name
        transport.addItems(withTitles: ["Webhook — existing receiver / blueprint", "Home Assistant integration — automatic entity"])
        transport.selectItem(at: config.integration ? 1 : 0)
        transport.target = self; transport.action = #selector(transportChanged)
        secret.placeholderString = "Stored credentials stay in Keychain; leave blank to keep them"
        button(useDefault, action: #selector(useDefaultAddress))
        useDefault.toolTip = "Fill the standard local address without saving or connecting."
        let addressRow = NSStackView(views: [server, useDefault]); addressRow.spacing = 8
        server.setAccessibilityLabel("Home Assistant URL")
        server.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        add(row("Home Assistant URL", addressRow), to: body)
        add(text("Use default fills homeassistant.local:8123. Local name discovery must work on your network; you can always enter an IP address or HTTPS URL."), to: body)
        add(row("Device name", deviceName), to: body)
        add(row("Connection method", transport), to: body)
        let secretRow = NSStackView(views: [secretLabel, secret])
        secretRow.orientation = .vertical; secretRow.alignment = .leading; secretRow.spacing = 5
        secret.widthAnchor.constraint(equalTo: secretRow.widthAnchor).isActive = true
        add(secretRow, to: body)
        button(signIn, action: #selector(logIn))
        button(importButton, action: #selector(importConnection))
        button(test, action: #selector(testConnection))
        let actions = NSStackView(views: [signIn, importButton, test]); actions.spacing = 8
        body.addArrangedSubview(actions)
        add(text("Install and add the Home Assistant integration before pairing. Sign-in and token import require an administrator only for setup. Ongoing reports send one boolean using a private webhook."), to: body)
        add(text("HTTPS is recommended. HTTP is accepted only for private IP addresses, localhost, .local or .lan names. Passwords are entered only in Home Assistant's sign-in window."), to: body)
        return body
    }

    private func outputView() -> NSStackView {
        let body = stack()
        profile.addItems(withTitles: OutputMode.allCases.map(\.title))
        profile.selectItem(at: OutputMode.allCases.firstIndex(of: config.output) ?? 0)
        profile.target = self; profile.action = #selector(outputChanged)
        target.stringValue = config.target
        target.placeholderString = "light.meeting_lamp"
        button(reload, action: #selector(loadEntities))
        let targetRow = NSStackView(views: [target, reload]); targetRow.spacing = 8
        target.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        add(row("Output type", profile), to: body)
        let targetGroup = row("Target entity", targetRow)
        self.targetGroup = targetGroup
        add(targetGroup, to: body)
        busyColor.color = color(config.busyColor); idleColor.color = color(config.idleColor)
        busyColor.setAccessibilityLabel("Meeting color"); idleColor.setAccessibilityLabel("Idle color")
        let colors = NSStackView(views: [NSTextField(labelWithString: "Meeting"), busyColor,
                                       NSTextField(labelWithString: "Idle"), idleColor, NSView()])
        colors.spacing = 10; body.addArrangedSubview(colors)
        brightness.doubleValue = Double(config.brightness)
        brightness.target = self; brightness.action = #selector(brightnessChanged)
        brightnessValue.stringValue = "\(config.brightness)%"
        brightnessValue.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let brightnessRow = row("Color light brightness", NSStackView(views: [brightness, brightnessValue]))
        add(brightnessRow, to: body)
        idleOff.state = config.idleOff ? .on : .off; body.addArrangedSubview(idleOff)
        colorGroups = [colors, brightnessRow, idleOff]
        offline.addItems(withTitles: ["Turn target off", "Leave target unchanged"])
        offline.selectItem(at: config.offlineHold ? 1 : 0)
        let offlineGroup = row("When reports stop", offline)
        self.offlineGroup = offlineGroup
        add(offlineGroup, to: body)
        add(text("Dashboard / status only creates a meeting entity and sends no light or switch commands. Use that entity for a tablet badge or any dashboard. Color mode requires a color-capable light. Disconnection never means idle/green."), to: body)
        add(text("Webhook mode keeps output configuration in Home Assistant automations / blueprints. Integration mode lets you configure it here or in Home Assistant's integration options."), to: body)
        return body
    }

    private func color(_ values: [Int]) -> NSColor {
        guard values.count == 3 else { return .systemRed }
        return NSColor(srgbRed: Double(values[0])/255, green: Double(values[1])/255, blue: Double(values[2])/255, alpha: 1)
    }
    private func rgb(_ well: NSColorWell) -> [Int] {
        let c = well.color.usingColorSpace(.sRGB) ?? .red
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }
    private var mode: OutputMode { OutputMode.allCases[max(0, profile.indexOfSelectedItem)] }
    private func updateControls() {
        let integration = transport.indexOfSelectedItem == 1
        for control in [server, deviceName, transport, secret, useDefault, importButton] as [NSControl] {
            control.isEnabled = !working
        }
        secretLabel.stringValue = integration ? "Access token (optional alternative to sign-in)" : "Webhook URL"
        secret.setAccessibilityLabel(secretLabel.stringValue)
        signIn.isEnabled = integration && !working
        profile.isEnabled = integration && !working
        target.isEnabled = integration && mode != .statusOnly && !working
        reload.isEnabled = target.isEnabled
        for control in [busyColor, idleColor, brightness] as [NSControl] {
            control.isEnabled = integration && mode == .lightColor && !working
        }
        targetGroup?.isHidden = !integration || mode == .statusOnly
        colorGroups.forEach { $0.isHidden = !integration || mode != .lightColor }
        offlineGroup?.isHidden = !integration || mode == .statusOnly
        save.title = integration ? "Save & pair" : "Save connection"
        idleOff.isEnabled = integration && mode == .lightColor && !working
        offline.isEnabled = integration && mode != .statusOnly && !working
        save.isEnabled = !working; test.isEnabled = !working; disconnect.isEnabled = !working
        refreshPermissionNotice()
        sendTest.toolTip = "Requires automatic call detection permission so the test can return to a known state after 10 seconds."
    }
    func refreshPermissionNotice() {
        let authorized = AXIsProcessTrusted()
        permissionNotice?.isHidden = authorized
        sendTest.isEnabled = store.hasConnection && !working && authorized
    }
    @objc private func transportChanged() { secret.stringValue = ""; updateControls() }
    @objc private func useDefaultAddress() {
        guard !working else { return }
        server.stringValue = EndpointPolicy.defaultServer
        status.stringValue = "Default address filled. Test the connection before saving; existing settings are unchanged."
    }
    @objc private func outputChanged() { target.removeAllItems(); updateControls() }
    @objc private func brightnessChanged() {
        brightnessValue.stringValue = "\(Int(brightness.doubleValue.rounded()))%"
    }
    private func serverURL() throws -> URL { try EndpointPolicy.validate(server.stringValue, base: true) }
    private func operation(_ body: @escaping () async throws -> String) {
        guard !working else { return }
        working = true; status.stringValue = "Working…"; updateControls()
        Task { @MainActor in
            do { status.stringValue = try await body() }
            catch { status.stringValue = (error as? ConnectionError)?.localizedDescription ?? "The operation could not be completed." }
            working = false; updateControls()
        }
    }
    private func importTypedToken(_ client: HomeAssistantClient) throws {
        let value = secret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            guard !value.contains("\n"), !value.contains("\r"), !value.contains(" ") else { throw ConnectionError.invalidSecret }
            // Explicit token replacement must not leave an older OAuth refresh token active.
            try client.store(value, kind: "access")
            CredentialStore.remove(CredentialStore.account(server: client.server, kind: "refresh"))
            secret.stringValue = ""
        }
    }
    @objc private func logIn() {
        operation { [self] in
            try await authentication.signIn(server: serverURL())
            secret.stringValue = ""
            return "Signed in. Use Save & pair to create or update the meeting entity."
        }
    }
    @objc private func loadEntities() {
        operation { [self] in
            let client = HomeAssistantClient(server: try serverURL())
            try importTypedToken(client)
            let entities = try await client.entities(mode: mode)
            target.removeAllItems(); target.addItems(withObjectValues: entities)
            return "\(entities.count) matching entities loaded. Choose one or type its entity ID."
        }
    }
    @objc private func testConnection() {
        operation { [self] in
            let url = try serverURL()
            if transport.indexOfSelectedItem == 1 {
                let client = HomeAssistantClient(server: url)
                try importTypedToken(client)
                _ = try await client.request(path: "api/", token: client.accessToken())
                return "Authenticated connection works. Save & pair checks integration and entity compatibility."
            }
            // Webhook IDs deliberately return success even when invalid. Never claim this verifies pairing.
            let client = HomeAssistantClient(server: url)
            do { _ = try await client.request(path: "api/") }
            catch ConnectionError.unauthorized { return "Home Assistant reachable. Webhook reception must be verified on its entity." }
            return "Server reachable. Webhook reception must be verified on its entity."
        }
    }
    @objc private func saveConnection() {
        operation { [self] in
            var next = config
            next.enabled = true; next.integration = transport.indexOfSelectedItem == 1
            next.server = try serverURL().absoluteString
            next.name = deviceName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.name.isEmpty, next.name.count <= 64 else { throw ConnectionError.invalidResponse }
            next.output = next.integration ? mode : .statusOnly
            next.target = next.output == .statusOnly ? "" : target.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            try next.output.validate(target: next.target)
            next.busyColor = rgb(busyColor); next.idleColor = rgb(idleColor)
            next.brightness = Int(brightness.doubleValue.rounded()); next.idleOff = idleOff.state == .on
            next.offlineHold = offline.indexOfSelectedItem == 1
            let webhook: String
            if next.integration {
                let client = HomeAssistantClient(server: try serverURL())
                try importTypedToken(client)
                (webhook, next.sourceEntity) = try await client.pair(next)
            } else {
                webhook = secret.stringValue.isEmpty ? (store.endpoint()?.absoluteString ?? "") : secret.stringValue
                next.sourceEntity = ""
            }
            try store.save(next, webhook: webhook)
            config = next; secret.stringValue = ""
            source.stringValue = next.sourceEntity.isEmpty ? "Meeting entity: configured by your webhook receiver." : "Meeting entity: " + next.sourceEntity
            onChange?()
            return next.integration ? "Paired and saved. The entity stays unavailable until the first fresh report." : "Webhook saved to Keychain. Verify reports on your Home Assistant entity."
        }
    }
    @objc private func testMeeting() {
        onTest?()
        status.stringValue = "Test meeting active for 10 seconds. Your manual timer and real call are preserved."
    }
    @objc private func disconnectConnection() {
        operation { [self] in
            store.disable()
            let activeServer = config.server.isEmpty ? server.stringValue : config.server
            if let url = try? EndpointPolicy.validate(activeServer, base: true) {
                await HomeAssistantClient(server: url).disconnect()
            }
            config.enabled = false
            onChange?()
            return "Disconnected. The receiver expires after 40 seconds; manual meeting timers remain local."
        }
    }
    @objc private func importConnection() {
        guard !working else { return }
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = false
        picker.message = "Import a private JSON connection file. It may contain a webhook URL or access token."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16_384 else { throw ConnectionError.invalidResponse }
            let data = try Data(contentsOf: url)
            guard data.count <= 16_384, let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(values.keys).isSubset(of: ["version", "server_url", "webhook_url", "access_token"]),
                  let address = values["server_url"] as? String else { throw ConnectionError.invalidResponse }
            if values["version"] != nil {
                guard let version = values["version"] as? Int, version == 1 else { throw ConnectionError.invalidResponse }
            }
            _ = try EndpointPolicy.validate(address, base: true)
            guard (values["webhook_url"] != nil) != (values["access_token"] != nil) else { throw ConnectionError.invalidSecret }
            if let webhook = values["webhook_url"] as? String {
                _ = try EndpointPolicy.validate(webhook); transport.selectItem(at: 0); secret.stringValue = webhook
            } else if let token = values["access_token"] as? String, !token.isEmpty {
                transport.selectItem(at: 1); secret.stringValue = token
            } else { throw ConnectionError.invalidSecret }
            server.stringValue = address
            status.stringValue = "Imported into this form. Review and Save to apply."
            updateControls()
        } catch { status.stringValue = "Invalid connection file. Expected server_url and either webhook_url or access_token." }
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
