import Foundation

public enum AnthropicError: Error, Equatable, Sendable, LocalizedError {
    case http(status: Int, type: String, message: String)
    case stream(type: String, message: String)
    case missingKey

    public var errorDescription: String? {
        switch self {
        case .http(let s, let t, let m): "HTTP \(s) \(t): \(m)"
        case .stream(let t, let m): "\(t): \(m)"
        case .missingKey: "No API key"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .http(let s, _, _): s == 429 || s == 529 || s >= 500
        case .stream(let t, _): t == "overloaded_error" || t == "api_error"
        case .missingKey: false
        }
    }
}

public struct AnthropicModel: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// web_search_20260209 needs Opus 4.6+/Sonnet 4.6+; Haiku 4.5 takes the basic variant.
    public var webSearchType: String
    /// Haiku 4.5 rejects `effort`.
    public var supportsEffort: Bool
    /// Server-side refusal fallback ("default" routing) on the Claude API.
    public var supportsFallbacks: Bool

    public static let opus55 = AnthropicModel(id: "claude-opus-5-5", label: "Opus 5.5", webSearchType: "web_search_20260209", supportsEffort: true, supportsFallbacks: true)
    public static let sonnet55 = AnthropicModel(id: "claude-sonnet-5-5", label: "Sonnet 5.5", webSearchType: "web_search_20260209", supportsEffort: true, supportsFallbacks: true)
    public static let haiku45 = AnthropicModel(id: "claude-haiku-4-5", label: "Haiku 4.5", webSearchType: "web_search_20250305", supportsEffort: false, supportsFallbacks: false)
    public static let all: [AnthropicModel] = [.opus55, .sonnet55, .haiku45]
}

/// Raw Messages API over URLSession (there is no official Swift SDK).
public struct AnthropicClient: Sendable {
    public var apiKey: String
    /// Required for organization-level keys that aren't scoped to a workspace.
    public var workspaceId: String?
    public var baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public var maxRetries = 3
    public var timeout: TimeInterval = 45
    /// Injectable for tests (URLProtocol stubs).
    public var session: URLSession = .shared

    public init(apiKey: String, workspaceId: String? = nil) {
        self.apiKey = apiKey
        let w = workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workspaceId = w?.isEmpty == false ? w : nil
    }

    /// One tiny real request, to tell a parent whether the key and settings work.
    /// Returns nil on success, or the API's own error message.
    public func check(model: String) async -> String? {
        let body: JSONValue = .object([
            "model": .string(model), "max_tokens": .number(16),
            "messages": .array([.object(["role": .string("user"), "content": .string("Reply with: ok")])]),
        ])
        do {
            for try await _ in stream(body: body) {}
            return nil
        } catch let e as AnthropicError {
            switch e {
            case .http(_, _, let message), .stream(_, let message): return message
            case .missingKey: return "No key"
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// Streams one request. `body` is a complete Messages API body; `stream: true` is added here.
    public func stream(body: JSONValue, betas: [String] = []) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var attempt = 0
                    var yielded = false
                    while true {
                        do {
                            try await streamOnce(body: body, betas: betas) { yielded = true; continuation.yield($0) }
                            continuation.finish()
                            return
                        } catch let e as AnthropicError where e.isRetryable && attempt < maxRetries && !yielded {
                            // Only retry before any event went out; a retry mid-stream would duplicate output.
                            attempt += 1
                            // Jittered exponential backoff: ~0.5s, 1s, 2s.
                            try await Task.sleep(for: .milliseconds(Int(500 * pow(2, Double(attempt - 1)) * Double.random(in: 0.8...1.2))))
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamOnce(body: JSONValue, betas: [String], yield: (JSONValue) -> Void) async throws {
        guard !apiKey.isEmpty else { throw AnthropicError.missingKey }
        guard case .object(var obj) = body else { preconditionFailure("body must be an object") }
        obj["stream"] = .bool(true)
        var req = URLRequest(url: baseURL, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
        if let workspaceId { req.setValue(workspaceId, forHTTPHeaderField: "anthropic-workspace-id") }
        req.httpBody = try JSONEncoder().encode(JSONValue.object(obj))

        let (bytes, response) = try await session.bytes(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let err = try? JSONDecoder().decode(JSONValue.self, from: data)
            throw AnthropicError.http(status: status,
                                      type: err?["error"]?["type"]?.stringValue ?? "http_error",
                                      message: err?["error"]?["message"]?.stringValue ?? String(decoding: data, as: UTF8.self))
        }
        for try await line in bytes.lines {
            if let event = try SSE.event(fromLine: line) { yield(event) }
        }
    }
}
