#if os(iOS)
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

/// "Continue with ChatGPT": OpenAI's Sign in with ChatGPT with plan usage, for open-source, locally run
/// apps. The first sign-in registers Hoop for this ChatGPT account (`client_id=dynamic_agent_client`) and
/// returns an issued `oaiapp_…` client id that later sign-ins reuse. The redirect is an HTTP loopback on
/// 127.0.0.1, which Hoop serves itself for the length of the sign-in.
///
/// Tokens live in the Keychain. The access token lasts an hour and is refreshed with the refresh token,
/// which lasts 30 days.
@MainActor
final class HoopChatGPTAuth: NSObject, ObservableObject {
    static let shared = HoopChatGPTAuth()

    struct Account: Codable, Equatable {
        var email: String?
        var name: String?
        var plan: String?
    }

    enum AuthError: LocalizedError {
        case cancelled
        case stateMismatch
        case missingCode
        case server(String)
        case invalidIdentity
        case signedOut

        var errorDescription: String? {
            switch self {
            case .cancelled: return String(localized: "Sign-in was cancelled.")
            case .stateMismatch, .invalidIdentity: return String(localized: "ChatGPT sign-in couldn't be verified. Please try again.")
            case .missingCode: return String(localized: "ChatGPT didn't return a sign-in code. Please try again.")
            case .server(let message): return message
            case .signedOut: return String(localized: "Sign in with ChatGPT to use Hoop AI.")
            }
        }
    }

    @Published private(set) var account: Account?
    @Published private(set) var isSigningIn = false

    var isSignedIn: Bool { account != nil && Keychain.read(.refreshToken) != nil }

    private static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let resource = "https://api.openai.com/v1"
    private static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    private static let callbackPath = "/auth/callback"
    private static let ports: [UInt16] = [1455, 1457, 1459]

    private var authSession: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?

    private override init() {
        super.init()
        if let data = Keychain.read(.account), let a = try? JSONDecoder().decode(Account.self, from: data),
           Keychain.read(.refreshToken) != nil {
            account = a
        }
    }

    /// A stable identifier for this install, sent as `ext_agent_host_id`.
    private var hostID: String {
        let key = "hoop.ai.hostID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: Sign in

    func signIn() async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false; authSession = nil }

        let verifier = Self.randomURLSafe(bytes: 48)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(bytes: 24)
        let nonce = Self.randomURLSafe(bytes: 24)
        let savedClientID = Keychain.readString(.clientID)

        let server = try await LoopbackServer.start(ports: Self.ports, path: Self.callbackPath)
        defer { server.stop() }
        let redirectURI = "http://127.0.0.1:\(server.port)\(Self.callbackPath)"

        var comps = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: savedClientID ?? "dynamic_agent_client"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes),
            .init(name: "resource", value: Self.resource),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        if savedClientID == nil {
            items.append(.init(name: "agent_name_hint", value: "Hoop"))
            items.append(.init(name: "ext_agent_host_id", value: hostID))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw AuthError.missingCode }

        // The browser sheet shares Safari's cookies, so someone already signed in to ChatGPT only confirms.
        // It never completes by itself: the loopback server receives the redirect, then the sheet is closed.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "hoop-chatgpt-loopback") { _, _ in
            server.cancel()
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        guard session.start() else { throw AuthError.cancelled }

        let callback: [String: String]
        do {
            callback = try await server.waitForCallback()
        } catch {
            session.cancel()
            throw AuthError.cancelled
        }
        session.cancel()

        if let err = callback["error"] {
            throw AuthError.server(callback["error_description"] ?? err)
        }
        guard callback["state"] == state else { throw AuthError.stateMismatch }
        guard let code = callback["code"] else { throw AuthError.missingCode }
        let clientID = callback["client_id"] ?? savedClientID ?? "dynamic_agent_client"

        let tokens = try await Self.tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": Self.resource,
        ])
        let audience = tokens.idToken.flatMap(Self.claims(of:)).map(Self.audience) ?? []
        guard let idToken = tokens.idToken, let claims = Self.claims(of: idToken),
              claims["nonce"] as? String == nonce,
              audience.isEmpty || audience.contains(clientID),
              (claims["exp"] as? Double).map({ $0 > Date().timeIntervalSince1970 - 60 }) ?? true
        else { throw AuthError.invalidIdentity }

        let newAccount = Self.account(from: claims)
        // A saved registration belongs to one ChatGPT account: never overwrite it with another's tokens.
        if let current = account, current.email != nil, newAccount.email != nil, current.email != newAccount.email,
           savedClientID != nil, callback["client_id"] == nil {
            throw AuthError.invalidIdentity
        }
        Keychain.save(Data(clientID.utf8), as: .clientID)
        store(tokens)
        if let data = try? JSONEncoder().encode(newAccount) { Keychain.save(data, as: .account) }
        account = newAccount
    }

    /// A valid access token, refreshing it first when it is within a minute of expiring.
    func accessToken() async throws -> String {
        if let token = Keychain.readString(.accessToken), let exp = Keychain.readString(.accessExpiry).flatMap(Double.init),
           exp > Date().timeIntervalSince1970 + 60 {
            return token
        }
        return try await refresh()
    }

    /// Forces a refresh (after a 401). Concurrent callers share one refresh so a rotating token isn't raced.
    @discardableResult
    func refresh() async throws -> String {
        if let running = refreshTask { return try await running.value }
        let task = Task<String, Error> { @MainActor in
            defer { refreshTask = nil }
            guard let refreshToken = Keychain.readString(.refreshToken),
                  let clientID = Keychain.readString(.clientID) else { throw AuthError.signedOut }
            do {
                let tokens = try await Self.tokenRequest([
                    "grant_type": "refresh_token",
                    "client_id": clientID,
                    "refresh_token": refreshToken,
                    "resource": Self.resource,
                ])
                store(tokens, keepingRefresh: refreshToken)
                return tokens.accessToken
            } catch AuthError.server(let message) where Self.isDeadGrant(message) {
                clearTokens()
                throw AuthError.signedOut
            }
        }
        refreshTask = task
        return try await task.value
    }

    /// Signs out locally and revokes the refresh token with OpenAI (best effort). The issued client id is
    /// kept so signing back in to the same ChatGPT account reuses Hoop's registration.
    func signOut() async {
        let refreshToken = Keychain.readString(.refreshToken)
        let clientID = Keychain.readString(.clientID)
        clearTokens()
        guard let refreshToken, let clientID else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.discoveryURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let endpoint = (json?["revocation_endpoint"] as? String).flatMap(URL.init(string:)) else { return }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(["token": refreshToken, "token_type_hint": "refresh_token", "client_id": clientID])
            _ = try? await URLSession.shared.data(for: request)
        } catch {}
    }

    private func clearTokens() {
        Keychain.delete(.accessToken)
        Keychain.delete(.accessExpiry)
        Keychain.delete(.refreshToken)
        Keychain.delete(.account)
        account = nil
    }

    private func store(_ tokens: TokenResponse, keepingRefresh oldRefresh: String? = nil) {
        Keychain.save(Data(tokens.accessToken.utf8), as: .accessToken)
        let expiry = Date().timeIntervalSince1970 + Double(tokens.expiresIn ?? 3600)
        Keychain.save(Data(String(expiry).utf8), as: .accessExpiry)
        if let r = tokens.refreshToken ?? oldRefresh { Keychain.save(Data(r.utf8), as: .refreshToken) }
    }

    // MARK: Token endpoint

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token", expiresIn = "expires_in"
        }
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = json?["error"] as? String ?? "HTTP \(status)"
            let description = json?["error_description"] as? String
            throw AuthError.server(description.map { "\(code): \($0)" } ?? code)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func isDeadGrant(_ message: String) -> Bool {
        ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
         "refresh_token_invalidated", "refresh_token_reused"].contains { message.hasPrefix($0) }
    }

    // MARK: Helpers

    private static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=:/?#[]@!$'()*,;")
        return fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private static func randomURLSafe(bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return base64url(Data(buffer))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The ID token's claims. The token comes straight from OpenAI's token endpoint over TLS, which
    /// vouches for its origin; the claims that tie it to this sign-in (nonce, audience, expiry) are checked.
    private static func claims(of jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func audience(_ claims: [String: Any]) -> [String] {
        if let a = claims["aud"] as? String { return [a] }
        return claims["aud"] as? [String] ?? []
    }

    private static func account(from claims: [String: Any]) -> Account {
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let plan = (auth?["chatgpt_plan_type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return Account(email: claims["email"] as? String, name: claims["name"] as? String, plan: plan)
    }
}

extension HoopChatGPTAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Loopback redirect server

/// A one-shot HTTP listener on 127.0.0.1 that receives the OAuth redirect and answers with a short page.
private final class LoopbackServer: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let path: String
    private let queue = DispatchQueue(label: "hoop.chatgpt.loopback")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    private init(listener: NWListener, port: UInt16, path: String) {
        self.listener = listener
        self.port = port
        self.path = path
    }

    /// Binds the first free port on the loopback interface. Binding failures (a port in use) arrive
    /// through the listener's state, so each attempt waits for `.ready` or `.failed` before moving on.
    static func start(ports: [UInt16], path: String) async throws -> LoopbackServer {
        var lastError: Error = HoopChatGPTAuth.AuthError.server(String(localized: "Couldn't start the sign-in."))
        for p in ports {
            guard let port = NWEndpoint.Port(rawValue: p) else { continue }
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: params, on: port) else { continue }
            let server = LoopbackServer(listener: listener, port: p, path: path)
            listener.newConnectionHandler = { [weak server] connection in server?.handle(connection) }
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let once = OnceFlag()
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if once.claim() { cont.resume() }
                        case .failed(let error):
                            if once.claim() { cont.resume(throwing: error) }
                        case .cancelled:
                            if once.claim() { cont.resume(throwing: HoopChatGPTAuth.AuthError.cancelled) }
                        default:
                            break
                        }
                    }
                    listener.start(queue: server.queue)
                }
                return server
            } catch {
                listener.cancel()
                lastError = error
            }
        }
        throw lastError
    }

    func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let result = self.result { cont.resume(with: result) } else { self.continuation = cont }
            }
        }
    }

    func cancel() {
        queue.async { self.finish(.failure(HoopChatGPTAuth.AuthError.cancelled)) }
    }

    func stop() {
        listener.cancel()
    }

    private func finish(_ r: Result<[String: String], Error>) {
        guard result == nil else { return }
        result = r
        continuation?.resume(with: r)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let target = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let comps = URLComponents(string: "http://127.0.0.1\(target)")
            let isCallback = comps?.path == self.path
            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;background:#000;color:#f5f5f7;text-align:center;padding-top:30vh\"><h2>Connected to Hoop</h2><p>You can return to the app.</p></body></html>"
                : "<html><body></body></html>"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard isCallback else { return }
            var params: [String: String] = [:]
            for item in comps?.queryItems ?? [] { params[item.name] = item.value ?? "" }
            self.finish(.success(params))
        }
    }
}

/// Resumes a continuation at most once from a callback that can fire repeatedly.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Keychain

private enum Keychain {
    enum Item: String {
        case accessToken = "access", accessExpiry = "accessExpiry", refreshToken = "refresh", clientID = "clientID", account = "account"
    }

    private static let service = "hoop.chatgpt"

    static func save(_ data: Data, as item: Item) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: item.rawValue]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ item: Item) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: item.rawValue,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func readString(_ item: Item) -> String? {
        read(item).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete(_ item: Item) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: item.rawValue]
        SecItemDelete(query as CFDictionary)
    }
}
#endif
