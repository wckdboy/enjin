import Foundation

/// USD per million tokens, for the spend cap. Keep in sync with Anthropic pricing.
public struct Pricing: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    /// 5-minute cache writes cost 1.25x input.
    public var cacheWrite: Double
    /// Per web search request.
    public static let webSearch = 10.0 / 1000

    public static func of(_ model: String) -> Pricing {
        switch model {
        case "claude-opus-5-5": Pricing(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5)
        case "claude-sonnet-5-5": Pricing(input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.5)
        case "claude-haiku-4-5": Pricing(input: 1, output: 5, cacheRead: 0.10, cacheWrite: 1.25)
        default: Pricing(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5) // assume the dearest current tier
        }
    }

    public func cost(_ u: MessageAccumulator.Usage, webSearches: Int = 0) -> Double {
        (Double(u.inputTokens) * input + Double(u.outputTokens) * output
            + Double(u.cacheReadInputTokens) * cacheRead + Double(u.cacheCreationInputTokens) * cacheWrite) / 1_000_000
            + Double(webSearches) * Self.webSearch
    }
}
