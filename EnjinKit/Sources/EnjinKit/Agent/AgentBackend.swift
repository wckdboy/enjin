import Foundation

/// A model that can run one agent turn over a Messages-API-shaped thread.
public protocol AgentBackend: Sendable {
    var modelId: String { get }
    var supportsWebSearch: Bool { get }
    /// On-device models get the reduced tool set and a compact prompt (plan §5.4).
    var isReduced: Bool { get }

    func run(thread: inout [JSONValue], system: String, tools: [JSONValue],
             onEvent: @escaping @Sendable (ProviderEvent) -> Void,
             execute: @escaping @Sendable (_ name: String, _ input: JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult
}

public struct AnthropicBackend: AgentBackend {
    public var client: AnthropicClient
    public var model: AnthropicModel
    public var effort: String?
    public var blockedDomains: [String]

    public var modelId: String { model.id }
    public var supportsWebSearch: Bool { true }
    public var isReduced: Bool { false }

    /// Short, static kid-safety blocklist for web search (plan §7).
    public static let defaultBlockedDomains = [
        "pornhub.com", "xvideos.com", "xnxx.com", "onlyfans.com", "chaturbate.com",
        "bet365.com", "pokerstars.com", "4chan.org", "8kun.top", "liveleak.com",
    ]

    public init(apiKey: String, workspaceId: String? = nil, model: AnthropicModel, effort: String? = "low",
                blockedDomains: [String] = AnthropicBackend.defaultBlockedDomains) {
        self.client = AnthropicClient(apiKey: apiKey, workspaceId: workspaceId)
        self.model = model
        self.effort = effort
        self.blockedDomains = blockedDomains
    }

    public func run(thread: inout [JSONValue], system: String, tools: [JSONValue],
                    onEvent: @escaping @Sendable (ProviderEvent) -> Void,
                    execute: @escaping @Sendable (String, JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult {
        var config = AgentConfig(model: model, system: system, tools: tools, effort: effort)
        config.blockedDomains = blockedDomains
        return try await AgentLoop(client: client, config: config).run(messages: &thread, onEvent: onEvent, executeTool: execute)
    }
}
