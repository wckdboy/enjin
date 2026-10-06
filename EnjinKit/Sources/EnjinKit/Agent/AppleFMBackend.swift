#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// On-device Apple Foundation Models: works without a key, no web search,
/// reduced tools and a compact prompt (plan §5.4).
@available(iOS 26.0, macOS 26.0, *)
public struct AppleFMBackend: AgentBackend {
    public let modelId = "apple-on-device"
    public let supportsWebSearch = false
    public let isReduced = true

    public init() {}

    /// Nil when the device can run it; otherwise a reason to show the parent.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This iPad can't run Apple's on-device model."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use Enjin without a key."
        case .unavailable(.modelNotReady): "Apple's on-device model is still downloading."
        case .unavailable: "Apple's on-device model isn't available."
        }
    }

    public func run(thread: inout [JSONValue], system: String, tools: [JSONValue],
                    onEvent: @escaping @Sendable (ProviderEvent) -> Void,
                    execute: @escaping @Sendable (String, JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult {
        let start = Date()
        // No history: the compact canvas summary in the last message is the whole context.
        let prompt = thread.last?["content"]?.stringValue ?? ""
        let session = LanguageModelSession(
            tools: [CreateCardsTool(execute: execute, onEvent: onEvent), UpdateCardTool(execute: execute, onEvent: onEvent)],
            instructions: Persona.compact)
        do {
            let response = try await session.respond(to: prompt)
            onEvent(.textDelta(response.content))
            onEvent(.stop(reason: "end_turn"))
            thread.append(.object(["role": .string("assistant"), "content": .string(response.content)]))
            return AgentTurnResult(stop: .done, rounds: 1, usage: .init(), firstEventMs: nil, totalMs: Date().timeIntervalSince(start) * 1000)
        } catch let e as LanguageModelSession.GenerationError {
            if case .guardrailViolation = e {
                return AgentTurnResult(stop: .refused, rounds: 1, usage: .init(), firstEventMs: nil, totalMs: Date().timeIntervalSince(start) * 1000)
            }
            throw e
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CreateCardsTool: Tool {
    let name = "createCards"
    let description = "Add up to 4 cards to the canvas, optionally inside a topic card."
    let execute: @Sendable (String, JSONValue) async -> ToolOutcome
    let onEvent: @Sendable (ProviderEvent) -> Void

    @Generable
    struct NewCard {
        @Guide(description: "Short title, under 60 characters")
        var title: String
        @Guide(description: "One or two short sentences, under 140 characters")
        var summary: String
        @Guide(description: "true for a follow-up idea the kid can explore later")
        var isStub: Bool
        @Guide(description: "Short search phrase for a real picture of this, or empty")
        var imageSearch: String
    }

    @Generable
    struct Arguments {
        @Guide(description: "Topic card id to put the cards inside, or empty for the current canvas")
        var parentCardId: String
        @Guide(description: "The cards to add", .maximumCount(4))
        var cards: [NewCard]
    }

    func call(arguments: Arguments) async throws -> String {
        var input: [String: JSONValue] = ["cards": .array(arguments.cards.map {
            .object(["title": .string($0.title), "summary": .string($0.summary), "isStub": .bool($0.isStub),
                     "image": $0.imageSearch.isEmpty ? .null : .string($0.imageSearch)])
        })]
        if !arguments.parentCardId.isEmpty { input["parentCardId"] = .string(arguments.parentCardId) }
        onEvent(.toolUse(id: UUID().uuidString, name: name, input: .object(input), raw: ""))
        switch await execute(name, .object(input)) {
        case .ok(let s), .error(let s): return s
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct UpdateCardTool: Tool {
    let name = "updateCard"
    let description = "Fill or fix one of your own cards."
    let execute: @Sendable (String, JSONValue) async -> ToolOutcome
    let onEvent: @Sendable (ProviderEvent) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "The card id")
        var cardId: String
        @Guide(description: "New summary, under 140 characters")
        var summary: String
        @Guide(description: "true once the card has real content")
        var filled: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let input: JSONValue = .object(["cardId": .string(arguments.cardId), "summary": .string(arguments.summary),
                                        "state": .string(arguments.filled ? "filled" : "stub")])
        onEvent(.toolUse(id: UUID().uuidString, name: name, input: input, raw: ""))
        switch await execute(name, input) {
        case .ok(let s), .error(let s): return s
        }
    }
}
#endif
