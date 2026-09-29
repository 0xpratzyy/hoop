#if os(iOS)
import Foundation

/// OpenAI's Responses API, authorised with the person's ChatGPT plan token (Sign in with ChatGPT).
/// Plan usage requires `store: false` and `stream: true` on every request and doesn't allow sampling
/// fields such as `temperature` or `max_output_tokens`, so none are sent.
enum HoopAIClient {
    struct Model: Identifiable, Hashable, Codable {
        let slug: String
        let displayName: String
        var id: String { slug }
    }

    /// One turn of input. Images are sent as data URLs.
    struct Turn {
        enum Role: String { case developer, user, assistant }
        var role: Role
        var text: String
        var imageJPEG: Data? = nil
    }

    enum AIError: LocalizedError {
        case signedOut
        case usageLimit
        case notEligible
        case unavailable
        case unsupported(String)
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .signedOut:
                return String(localized: "Sign in with ChatGPT again to keep using Hoop AI.")
            case .usageLimit:
                return String(localized: "Hoop has reached its usage limit on your ChatGPT plan. You can raise it in ChatGPT settings.")
            case .notEligible:
                return String(localized: "Your ChatGPT account can't share plan usage with Hoop yet.")
            case .unavailable:
                return String(localized: "ChatGPT is busy right now. Try again in a moment.")
            case .unsupported(let m):
                return m
            case .http(let status, let m):
                return m.isEmpty ? String(localized: "Hoop AI couldn't answer (error \(status)).") : m
            case .empty:
                return String(localized: "Hoop AI didn't return an answer. Try again.")
            }
        }

        var isUsageLimit: Bool { if case .usageLimit = self { return true } else { return false } }
    }

    private static let base = URL(string: "https://api.openai.com/v1")!

    // MARK: Models

    static func models() async throws -> [Model] {
        let data = try await authorised { token in
            var request = URLRequest(url: base.appendingPathComponent("models"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = json?["data"] as? [[String: Any]] ?? json?["models"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            if let visibility = row["visibility"] as? String, visibility != "list" { return nil }
            guard let slug = (row["slug"] as? String) ?? (row["id"] as? String) else { return nil }
            let name = (row["display_name"] as? String) ?? slug
            return Model(slug: slug, displayName: name)
        }
    }

    // MARK: Streaming responses

    /// Streams the reply's text. Finishes only on `response.completed`, as the plan-usage docs require.
    static func stream(model: String, turns: [Turn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamOnce(model: model, turns: turns, retryOn401: true) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole reply as one string.
    static func complete(model: String, turns: [Turn]) async throws -> String {
        var text = ""
        for try await delta in stream(model: model, turns: turns) { text += delta }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AIError.empty }
        return trimmed
    }

    private static func streamOnce(model: String, turns: [Turn], retryOn401: Bool,
                                   onDelta: @escaping (String) -> Void) async throws {
        let token = try await tokenOrSignedOut()
        var request = URLRequest(url: base.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body(model: model, turns: turns))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var raw = Data()
            for try await b in bytes { raw.append(b); if raw.count > 32_768 { break } }
            if status == 401, retryOn401 {
                _ = try? await HoopChatGPTAuth.shared.refresh()
                try await streamOnce(model: model, turns: turns, retryOn401: false, onDelta: onDelta)
                return
            }
            throw mapError(status: status, body: raw)
        }

        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                if let delta = event["delta"] as? String { onDelta(delta) }
            case "response.completed":
                completed = true
            case "response.failed", "error":
                let err = (event["response"] as? [String: Any])?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
                throw mapError(code: err["code"] as? String, message: err["message"] as? String, status: 500)
            default:
                continue
            }
            if completed { break }
        }
        if !completed { throw AIError.unavailable }
    }

    private static func body(model: String, turns: [Turn]) -> [String: Any] {
        let input: [[String: Any]] = turns.map { turn in
            if let jpeg = turn.imageJPEG {
                return ["role": turn.role.rawValue,
                        "content": [["type": "input_text", "text": turn.text],
                                    ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]]
            }
            return ["role": turn.role.rawValue, "content": turn.text]
        }
        return ["model": model, "input": input, "store": false, "stream": true]
    }

    // MARK: Errors

    private static func mapError(status: Int, body: Data) -> AIError {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let err = json?["error"] as? [String: Any]
        return mapError(code: (err?["code"] as? String) ?? (err?["type"] as? String), message: err?["message"] as? String, status: status)
    }

    private static func mapError(code: String?, message: String?, status: Int) -> AIError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .usageLimit
        case "subscription_sharing_user_not_eligible": return .notEligible
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return .unavailable
        case "subscription_sharing_invalid_user": return .signedOut
        case "subscription_sharing_unsupported_capability": return .unsupported(message ?? String(localized: "That request isn't supported on your ChatGPT plan."))
        default: break
        }
        switch status {
        case 401: return .signedOut
        case 429: return .usageLimit
        case 503: return .unavailable
        default: return .http(status, message ?? "")
        }
    }

    // MARK: Auth plumbing

    private static func tokenOrSignedOut() async throws -> String {
        do { return try await HoopChatGPTAuth.shared.accessToken() } catch { throw AIError.signedOut }
    }

    /// A GET-style request with one retry after a token refresh on 401.
    private static func authorised(_ make: (String) -> URLRequest) async throws -> Data {
        var token = try await tokenOrSignedOut()
        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: make(token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            if status == 401, attempt == 0, let fresh = try? await HoopChatGPTAuth.shared.refresh() {
                token = fresh
                continue
            }
            throw mapError(status: status, body: data)
        }
        throw AIError.signedOut
    }
}
#endif
