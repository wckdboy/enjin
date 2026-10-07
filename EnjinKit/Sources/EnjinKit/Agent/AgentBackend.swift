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

/// What a turn may cost at most: output tokens (and web search, where there is any).
public struct TurnBudget: Sendable, Equatable {
    public var maxTokens: Int
    public var webSearch: Bool
    public init(maxTokens: Int, webSearch: Bool) { self.maxTokens = maxTokens; self.webSearch = webSearch }
    /// Building a world: cards with figures and module specs.
    public static let build = TurnBudget(maxTokens: 12_000, webSearch: true)
    /// A line, a question, a note to self.
    public static let small = TurnBudget(maxTokens: 900, webSearch: false)
}

/// Backends that can be held to a budget per turn.
public protocol BudgetedBackend: AgentBackend {
    func run(thread: inout [JSONValue], system: String, tools: [JSONValue], budget: TurnBudget,
             onEvent: @escaping @Sendable (ProviderEvent) -> Void,
             execute: @escaping @Sendable (_ name: String, _ input: JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult
}

public struct AnthropicBackend: BudgetedBackend {
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
        try await run(thread: &thread, system: system, tools: tools, budget: .build, onEvent: onEvent, execute: execute)
    }

    public func run(thread: inout [JSONValue], system: String, tools: [JSONValue], budget: TurnBudget,
                    onEvent: @escaping @Sendable (ProviderEvent) -> Void,
                    execute: @escaping @Sendable (String, JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult {
        var config = AgentConfig(model: model, system: system, tools: tools, effort: model.supportsEffort ? effort : nil)
        config.maxTokens = budget.maxTokens
        config.webSearch = budget.webSearch
        config.blockedDomains = blockedDomains
        config.endAfterClientTools = true
        // Search results are big (input tokens) and slow; one per turn is plenty for a kid's question.
        config.maxWebSearches = 1
        return try await AgentLoop(client: client, config: config).run(messages: &thread, onEvent: onEvent, executeTool: execute)
    }
}
