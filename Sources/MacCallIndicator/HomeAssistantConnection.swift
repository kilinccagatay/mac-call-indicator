import Foundation
import Security
import CryptoKit

enum ConnectionError: Error, LocalizedError {
    case invalidURL, invalidTarget, invalidSecret, keychain, unauthorized, unavailable, missingIntegration, invalidResponse, unsupportedOAuth
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use HTTPS, or HTTP on a private local network. Do not include credentials, query parameters, or a fragment."
        case .invalidTarget: return "Choose an entity matching the output type. Dashboard mode needs no target."
        case .invalidSecret: return "Enter a webhook URL or sign in / import a valid access token."
        case .keychain: return "The credential could not be saved to macOS Keychain."
        case .unauthorized: return "Sign in again. Pairing requires a Home Assistant administrator."
        case .unavailable: return "Home Assistant could not be reached. Check its address and network."
        case .missingIntegration: return "Install and add the Mac Call Indicator integration in Home Assistant first."
        case .invalidResponse: return "Home Assistant rejected the request or returned an unexpected response."
        case .unsupportedOAuth: return "This Home Assistant version does not advertise PKCE sign-in. Update it or import a long-lived access token instead."
        }
    }
}

enum EndpointPolicy {
    static let defaultServer = "http://homeassistant.local:8123/"
    static func validate(_ value: String, base: Bool = false) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw ConnectionError.invalidURL }
        if base && !["", "/"].contains(url.path) { throw ConnectionError.invalidURL }
        if url.scheme?.lowercased() == "http" && !isPrivateHost(host) { throw ConnectionError.invalidURL }
        return url
    }
    static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") { return true }
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "::1" || (h.contains(":") && (h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe80:"))) { return true }
        let raw = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = raw.compactMap { Int($0) }
        guard raw.count == 4, parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && (16...31).contains(parts[1]))
    }
}

enum OutputMode: String, Codable, CaseIterable {
    case statusOnly = "status_only", lightOnOff = "light_onoff", lightColor = "light_color"
    case smartSwitch = "switch", inputBoolean = "input_boolean"
    var title: String {
        switch self {
        case .statusOnly: return "Dashboard / status only"
        case .lightOnOff: return "Light — on/off"
        case .lightColor: return "Light — color"
        case .smartSwitch: return "Switch"
        case .inputBoolean: return "Input boolean"
        }
    }
    var domain: String? {
        switch self {
        case .statusOnly: return nil
        case .lightOnOff, .lightColor: return "light"
        case .smartSwitch: return "switch"
        case .inputBoolean: return "input_boolean"
        }
    }
    func validate(target: String) throws {
        if self == .statusOnly { return }
        let parts = target.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == domain, !parts[1].isEmpty,
              target.range(of: #"^[a-z_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil else { throw ConnectionError.invalidTarget }
    }
}

struct ConnectionSettings: Codable {
    var enabled = true
    var integration = false
    var server = ""
    var deviceID = UUID().uuidString
    var name = "Meeting indicator"
    var output = OutputMode.statusOnly
    var target = ""
    var busyColor = [255, 0, 0]
    var idleColor = [0, 255, 0]
    var brightness = 60
    var idleOff = false
    var offlineHold = false
    var sourceEntity = ""
    var pairingBody: [String: Any] {
        ["client_id": deviceID, "name": name, "output_mode": output.rawValue,
         "target_entity": output == .statusOnly ? "" : target, "busy_color": busyColor, "idle_color": idleColor,
         "brightness_pct": brightness, "idle_off": idleOff, "offline_action": offlineHold ? "hold" : "off"]
    }
}

enum CredentialStore {
    private static let service = "local.MacCallIndicator.HomeAssistant"
    static func account(server: URL, kind: String) -> String {
        let origin = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return kind + ":" + SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecReturnData as String: true,
                                   kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(attributes) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ConnectionError.keychain }
        } else if status != errSecSuccess { throw ConnectionError.keychain }
    }
    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

final class ConnectionStore {
    static let shared = ConnectionStore()
    private let lock = NSLock()
    private let key = "homeAssistantConnectionV1"
    var settings: ConnectionSettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(ConnectionSettings.self, from: data) else { return ConnectionSettings() }
        return config
    }
    var configured: Bool { UserDefaults.standard.data(forKey: key) != nil }
    func endpoint() -> URL? {
        guard configured else {
            return webhookURL().flatMap { try? EndpointPolicy.validate($0.absoluteString) }
        }
        let config = settings
        guard config.enabled, let secret = CredentialStore.read("receiver") else { return nil }
        return try? EndpointPolicy.validate(secret)
    }
    func save(_ settings: ConnectionSettings, webhook: String) throws {
        let url = try EndpointPolicy.validate(webhook)
        guard url.path.hasPrefix("/api/webhook/"), url.path.count > 13 else { throw ConnectionError.invalidSecret }
        let data = try JSONEncoder().encode(settings)
        lock.lock(); defer { lock.unlock() }
        try CredentialStore.write(url.absoluteString, account: "receiver")
        UserDefaults.standard.set(data, forKey: key)
    }
    func disable() {
        var config = settings
        config.enabled = false
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: key) }
        CredentialStore.remove("receiver")
    }
}

final class HomeAssistantClient {
    static let clientID = "https://raw.githubusercontent.com/kilinccagatay/mac-call-indicator/main/oauth-client.html"
    let server: URL
    init(server: URL) { self.server = server }
    func credential(_ kind: String) -> String? { CredentialStore.read(CredentialStore.account(server: server, kind: kind)) }
    func store(_ value: String, kind: String) throws {
        try CredentialStore.write(value, account: CredentialStore.account(server: server, kind: kind))
    }
    func request(path: String, method: String = "GET", token: String? = nil, json: [String: Any]? = nil,
                 form: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path), timeoutInterval: 8)
        request.httpMethod = method
        if let token = token {
            guard !token.contains("\n"), !token.contains("\r") else { throw ConnectionError.invalidSecret }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let json = json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let form = form {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            request.httpBody = Data(form.sorted(by: { $0.key < $1.key }).map {
                ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" +
                ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
            }.joined(separator: "&").utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ConnectionError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw ConnectionError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ConnectionError.unauthorized }
        if http.statusCode == 404 && path.contains("mac_call_indicator") { throw ConnectionError.missingIntegration }
        guard (200..<300).contains(http.statusCode), data.count < 8_000_000 else { throw ConnectionError.invalidResponse }
        return data
    }
    func accessToken() async throws -> String {
        if let refresh = credential("refresh") {
            let data = try await request(path: "auth/token", method: "POST",
                form: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": Self.clientID])
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = result["access_token"] as? String else { throw ConnectionError.invalidResponse }
            try store(token, kind: "access")
            return token
        }
        guard let token = credential("access"), !token.isEmpty else { throw ConnectionError.invalidSecret }
        return token
    }
    func pair(_ settings: ConnectionSettings) async throws -> (String, String) {
        let data = try await request(path: "api/mac_call_indicator/pair", method: "POST",
                                     token: accessToken(), json: settings.pairingBody)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = result["webhook_path"] as? String, path.hasPrefix("/api/webhook/"),
              !path.contains("?"), !path.contains("#"), !path.contains(".."),
              let entity = result["entity_id"] as? String, entity.hasPrefix("binary_sensor.") else { throw ConnectionError.invalidResponse }
        return (server.appendingPathComponent(String(path.dropFirst())).absoluteString, entity)
    }
    func entities(mode: OutputMode) async throws -> [String] {
        guard let domain = mode.domain else { return [] }
        let data = try await request(path: "api/states", token: accessToken())
        guard let states = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ConnectionError.invalidResponse }
        return states.compactMap { state in
            guard let id = state["entity_id"] as? String, id.hasPrefix(domain + ".") else { return nil }
            if mode == .lightColor {
                let attrs = state["attributes"] as? [String: Any] ?? [:]
                let colors = Set(attrs["supported_color_modes"] as? [String] ?? [])
                guard !colors.isDisjoint(with: ["hs", "xy", "rgb", "rgbw", "rgbww"]) else { return nil }
            }
            return id
        }.sorted()
    }
    func disconnect() async {
        if let refresh = credential("refresh") {
            _ = try? await request(path: "auth/revoke", method: "POST", form: ["token": refresh])
        }
        CredentialStore.remove(CredentialStore.account(server: server, kind: "access"))
        CredentialStore.remove(CredentialStore.account(server: server, kind: "refresh"))
    }
}
