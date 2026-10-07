import Foundation

public struct AgentConfig: Sendable {
    public var model: AnthropicModel
    public var system: String
    /// Client tool definitions (name/description/input_schema).
    public var tools: [JSONValue]
    public var effort: String?
    public var webSearch = true
    public var maxWebSearches = 3
    /// Kid-safety blocklist for the server web search tool.
    public var blockedDomains: [String] = []
    public var maxRounds = 5
    public var maxTokens = 16_000
    /// Keep the static prefix (tools + system) cached for an hour, not five minutes: explorers
    /// pause to read and play, and every expired prefix is paid for again at the write price.
    public var longCache = true
    /// End the turn as soon as the model's client tool calls all succeed, instead
    /// of sending the results back for another round just to say "done". The
    /// results are returned as `pendingToolResults` and must open the next user
    /// message. Saves a full request (time and money) on nearly every turn.
    public var endAfterClientTools = false

    public init(model: AnthropicModel, system: String, tools: [JSONValue], effort: String? = "low") {
        self.model = model; self.system = system; self.tools = tools; self.effort = effort
    }
}

public enum ToolOutcome: Sendable {
    case ok(String)
    case error(String)
}

public enum AgentStop: Equatable, Sendable {
    case done
    case refused
    case truncated
    case roundLimit
}

public struct AgentTurnResult: Sendable {
    public var stop: AgentStop
    public var rounds: Int
    public var usage: MessageAccumulator.Usage
    /// Time from request start to the first streamed event.
    public var firstEventMs: Double?
    public var totalMs: Double
    /// tool_result blocks the next user message must start with (see endAfterClientTools).
    public var pendingToolResults: [JSONValue] = []
    public var webSearches = 0

    public init(stop: AgentStop, rounds: Int, usage: MessageAccumulator.Usage, firstEventMs: Double?, totalMs: Double) {
        self.stop = stop; self.rounds = rounds; self.usage = usage; self.firstEventMs = firstEventMs; self.totalMs = totalMs
    }
}

/// Manual tool-use loop: model turn -> run client tools -> feed results -> repeat.
/// Appends every message to `messages`, so the caller owns the transcript and it
/// stays append-only (required for thinking blocks to stay valid).
public struct AgentLoop: Sendable {
    public var client: AnthropicClient
    public var config: AgentConfig

    public init(client: AnthropicClient, config: AgentConfig) {
        self.client = client; self.config = config
    }

    public func body(messages: [JSONValue]) -> (JSONValue, [String]) {
        var tools = config.tools.map { tool -> JSONValue in
            guard case .object(var t) = tool else { return tool }
            t["eager_input_streaming"] = .bool(true)
            return .object(t)
        }
        if config.webSearch {
            var ws: [String: JSONValue] = ["type": .string(config.model.webSearchType), "name": .string("web_search"),
                                           "max_uses": .number(Double(config.maxWebSearches))]
            if !config.blockedDomains.isEmpty { ws["blocked_domains"] = .array(config.blockedDomains.map { .string($0) }) }
            tools.append(.object(ws))
        }
        var body: [String: JSONValue] = [
            "model": .string(config.model.id),
            "max_tokens": .number(Double(config.maxTokens)),
            "system": .array([.object(config.longCache
                ? ["type": .string("text"), "text": .string(config.system), "cache_control": .object(["type": .string("ephemeral"), "ttl": .string("1h")])]
                : ["type": .string("text"), "text": .string(config.system)])]),
            "tools": .array(tools),
            "messages": .array(messages),
            // Auto-places a cache breakpoint on the last cacheable block each turn.
            "cache_control": .object(["type": .string("ephemeral")]),
        ]
        var betas: [String] = []
        if let effort = config.effort, config.model.supportsEffort {
            body["output_config"] = .object(["effort": .string(effort)])
        }
        if config.model.supportsFallbacks {
            body["fallbacks"] = .string("default")
            betas.append("server-side-fallback-2026-07-01")
        }
        return (.object(body), betas)
    }

    public func run(
        messages: inout [JSONValue],
        onEvent: @escaping @Sendable (ProviderEvent) -> Void,
        executeTool: @escaping @Sendable (_ name: String, _ input: JSONValue) async -> ToolOutcome
    ) async throws -> AgentTurnResult {
        let start = Date()
        var firstEvent: Double?
        var usage = MessageAccumulator.Usage()
        var searches = 0

        for round in 1...config.maxRounds {
            try Task.checkCancellation()
            let (body, betas) = body(messages: messages)
            var acc = MessageAccumulator()
            var toolCalls: [(id: String, name: String, input: JSONValue?, raw: String)] = []
            for try await event in client.stream(body: body, betas: betas) {
                if firstEvent == nil { firstEvent = Date().timeIntervalSince(start) * 1000 }
                for e in try acc.apply(event) {
                    if case .toolUse(let id, let name, let input, let raw) = e { toolCalls.append((id, name, input, raw)) }
                    if case .serverToolUse = e { searches += 1 }
                    onEvent(e)
                }
            }
            usage.inputTokens += acc.usage.inputTokens
            usage.outputTokens += acc.usage.outputTokens
            usage.cacheReadInputTokens += acc.usage.cacheReadInputTokens
            usage.cacheCreationInputTokens += acc.usage.cacheCreationInputTokens
            messages.append(.object(["role": .string("assistant"), "content": .array(acc.content.filter { $0 != .null })]))

            let elapsed = { Date().timeIntervalSince(start) * 1000 }
            switch acc.stopReason {
            case "pause_turn":
                // Server tool loop hit its limit; resend as-is and it resumes.
                continue
            case "refusal":
                return AgentTurnResult(stop: .refused, rounds: round, usage: usage, firstEventMs: firstEvent, totalMs: elapsed())
            case "max_tokens":
                // A tool input may be cut off mid-JSON: never run this turn's tools.
                return AgentTurnResult(stop: .truncated, rounds: round, usage: usage, firstEventMs: firstEvent, totalMs: elapsed())
            case "tool_use":
                var results: [JSONValue] = []
                for call in toolCalls {
                    let outcome: ToolOutcome = if let input = call.input { await executeTool(call.name, input) }
                        else { .error(#"{"INVALID_JSON": \#(JSONValue.string(call.raw).jsonString)}"#) }
                    var r: [String: JSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(call.id)]
                    switch outcome {
                    case .ok(let s): r["content"] = .string(s)
                    case .error(let s): r["content"] = .string(s); r["is_error"] = .bool(true)
                    }
                    results.append(.object(r))
                }
                if config.endAfterClientTools && results.allSatisfy({ $0["is_error"] == nil }) {
                    var r = AgentTurnResult(stop: .done, rounds: round, usage: usage, firstEventMs: firstEvent, totalMs: elapsed())
                    r.pendingToolResults = results
                    r.webSearches = searches
                    return r
                }
                // All results in one user message, so the model keeps making parallel calls.
                messages.append(.object(["role": .string("user"), "content": .array(results)]))
            default:
                var r = AgentTurnResult(stop: .done, rounds: round, usage: usage, firstEventMs: firstEvent, totalMs: elapsed())
                r.webSearches = searches
                return r
            }
        }
        return AgentTurnResult(stop: .roundLimit, rounds: config.maxRounds, usage: usage, firstEventMs: firstEvent,
                               totalMs: Date().timeIntervalSince(start) * 1000)
    }
}

extension JSONValue {
    var jsonString: String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "null"
    }
}
