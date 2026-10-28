import AppKit
import AuthenticationServices
import CryptoKit
import Security

enum OAuthPKCE {
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ConnectionError.invalidResponse }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func code(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == "mac-call-indicator", callback.host == "auth",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "state" }).count == 1,
              parts.queryItems?.first(where: { $0.name == "state" })?.value == expectedState,
              parts.queryItems?.filter({ $0.name == "code" }).count == 1,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw ConnectionError.unauthorized
        }
        return code
    }
}

@MainActor final class HomeAssistantSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    weak var window: NSWindow?
    private var session: ASWebAuthenticationSession?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? NSWindow()
    }
    func signIn(server: URL) async throws {
        let client = HomeAssistantClient(server: server)
        // Older HA versions silently ignored PKCE. Never downgrade a native
        // client to an unprotected authorization-code exchange.
        guard let discovery = try? await client.request(path: ".well-known/oauth-authorization-server"),
              let metadata = try? JSONSerialization.jsonObject(with: discovery) as? [String: Any],
              (metadata["code_challenge_methods_supported"] as? [String])?.contains("S256") == true else {
            throw ConnectionError.unsupportedOAuth
        }
        let verifier = try OAuthPKCE.random(), state = try OAuthPKCE.random()
        var url = URLComponents(url: server.appendingPathComponent("auth/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: HomeAssistantClient.clientID),
            URLQueryItem(name: "redirect_uri", value: "mac-call-indicator://auth"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: OAuthPKCE.challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "mac-call-indicator") { url, _ in
                if let url = url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: ConnectionError.unauthorized) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() { continuation.resume(throwing: ConnectionError.unavailable) }
        }
        defer { session = nil }
        let code = try OAuthPKCE.code(from: callback, expectedState: state)
        let data = try await client.request(path: "auth/token", method: "POST", form: [
            "grant_type": "authorization_code", "code": code, "client_id": HomeAssistantClient.clientID,
            "code_verifier": verifier
        ])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = result["access_token"] as? String, let refresh = result["refresh_token"] as? String else {
            throw ConnectionError.invalidResponse
        }
        try client.store(refresh, kind: "refresh")
        try client.store(access, kind: "access")
    }
}
