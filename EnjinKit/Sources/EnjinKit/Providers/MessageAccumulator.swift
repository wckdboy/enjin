import Foundation

/// What the agent loop and UI care about while a response streams in.
public enum ProviderEvent: Equatable, Sendable {
    case textDelta(String)
    /// A client tool call, complete and parsed. `input` is nil if the JSON was invalid.
    case toolUse(id: String, name: String, input: JSONValue?, raw: String)
    /// A client tool's input so far, while it streams (raw partial JSON).
    case toolInputProgress(id: String, name: String, partial: String)
    case serverToolUse(name: String, input: JSONValue)
    case webSearchResults([WebResult])
    case webSearchError(String)
    case citation(WebResult, citedText: String)
    case stop(reason: String)

    public struct WebResult: Equatable, Sendable, Hashable {
        public var title: String
        public var url: String
    }
}

/// Rebuilds the assistant message from stream events. The finished `content`
/// must be sent back verbatim on the next turn (thinking blocks + signatures,
/// server tool blocks, citations), so we keep every block whole rather than
/// just the text.
public struct MessageAccumulator: Sendable {
    public private(set) var content: [JSONValue] = []
    public private(set) var stopReason: String?
    public private(set) var usage = Usage()
    public private(set) var messageId: String?
    private var partialJSON: [Int: String] = [:]

    public struct Usage: Equatable, Sendable {
        public var inputTokens = 0
        public var outputTokens = 0
        public var cacheReadInputTokens = 0
        public var cacheCreationInputTokens = 0
        public init() {}
    }

    public init() {}

    public mutating func apply(_ event: JSONValue) throws -> [ProviderEvent] {
        guard let type = event["type"]?.stringValue else { return [] }
        switch type {
        case "message_start":
            messageId = event["message"]?["id"]?.stringValue
            if let u = event["message"]?["usage"] { mergeUsage(u) }
            return []

        case "content_block_start":
            guard let index = event["index"]?.intValue, case .object(let block)? = event["content_block"] else { return [] }
            // Tool inputs arrive as input_json_delta fragments; start empty.
            if block["type"]?.stringValue == "tool_use" || block["type"]?.stringValue == "server_tool_use" {
                partialJSON[index] = ""
            }
            set(index, .object(block))
            return startEvents(for: .object(block))

        case "content_block_delta":
            guard let index = event["index"]?.intValue, let delta = event["delta"], index < content.count,
                  case .object(var block) = content[index] else { return [] }
            var out: [ProviderEvent] = []
            switch delta["type"]?.stringValue {
            case "text_delta":
                let t = delta["text"]?.stringValue ?? ""
                block["text"] = .string((block["text"]?.stringValue ?? "") + t)
                out.append(.textDelta(t))
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"]?.stringValue ?? ""
                if block["type"]?.stringValue == "tool_use" {
                    out.append(.toolInputProgress(id: block["id"]?.stringValue ?? "", name: block["name"]?.stringValue ?? "", partial: partialJSON[index] ?? ""))
                }
            case "thinking_delta":
                block["thinking"] = .string((block["thinking"]?.stringValue ?? "") + (delta["thinking"]?.stringValue ?? ""))
            case "signature_delta":
                block["signature"] = delta["signature"]
            case "citations_delta":
                if let c = delta["citation"] {
                    var list: [JSONValue] = if case .array(let a)? = block["citations"] { a } else { [] }
                    list.append(c)
                    block["citations"] = .array(list)
                    if let url = c["url"]?.stringValue {
                        out.append(.citation(.init(title: c["title"]?.stringValue ?? url, url: url), citedText: c["cited_text"]?.stringValue ?? ""))
                    }
                }
            default:
                break
            }
            content[index] = .object(block)
            return out

        case "content_block_stop":
            guard let index = event["index"]?.intValue, index < content.count, let raw = partialJSON.removeValue(forKey: index),
                  case .object(var block) = content[index] else { return [] }
            let parsed = raw.isEmpty ? JSONValue.object([:]) : try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
            // Echo back valid input; invalid input is reported to the model as an error result by the loop.
            block["input"] = parsed ?? .object([:])
            content[index] = .object(block)
            let name = block["name"]?.stringValue ?? ""
            if block["type"]?.stringValue == "server_tool_use" {
                return [.serverToolUse(name: name, input: parsed ?? .null)]
            }
            return [.toolUse(id: block["id"]?.stringValue ?? "", name: name, input: parsed, raw: raw)]

        case "message_delta":
            if let r = event["delta"]?["stop_reason"]?.stringValue { stopReason = r }
            if let u = event["usage"] { mergeUsage(u) }
            return []

        case "message_stop":
            return [.stop(reason: stopReason ?? "end_turn")]

        case "error":
            throw AnthropicError.stream(type: event["error"]?["type"]?.stringValue ?? "error",
                                        message: event["error"]?["message"]?.stringValue ?? "stream error")
        default:
            return [] // ping and future event types
        }
    }

    private mutating func set(_ index: Int, _ block: JSONValue) {
        while content.count <= index { content.append(.null) }
        content[index] = block
    }

    private func startEvents(for block: JSONValue) -> [ProviderEvent] {
        guard block["type"]?.stringValue == "web_search_tool_result" else { return [] }
        switch block["content"] {
        case .array(let results):
            return [.webSearchResults(results.compactMap { r in
                r["url"]?.stringValue.map { .init(title: r["title"]?.stringValue ?? $0, url: $0) }
            })]
        case .object(let err):
            // Server-tool errors arrive as a 200 with an error object, not a raised error.
            return [.webSearchError(err["error_code"]?.stringValue ?? "unknown")]
        default:
            return []
        }
    }

    private mutating func mergeUsage(_ u: JSONValue) {
        if let n = u["input_tokens"]?.intValue { usage.inputTokens = n }
        if let n = u["output_tokens"]?.intValue { usage.outputTokens = n }
        if let n = u["cache_read_input_tokens"]?.intValue { usage.cacheReadInputTokens = n }
        if let n = u["cache_creation_input_tokens"]?.intValue { usage.cacheCreationInputTokens = n }
    }
}

extension JSONValue {
    public var intValue: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }
}
