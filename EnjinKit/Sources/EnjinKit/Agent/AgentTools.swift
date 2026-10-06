import Foundation

/// Client tool definitions and their validated inputs (plan §5.3).
public enum AgentTools {
    public static let maxCardsPerCall = 4
    public static let maxCardsPerTurn = 6
    public static let titleLimit = 60
    public static let summaryLimit = 140
    public static let bodyLimit = 600

    private static func string(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    public static let createCards: JSONValue = .object([
        "name": .string("createCards"),
        "description": .string("Add up to 4 cards to the canvas. They go into the portal the kid is looking at, or inside parentCardId's portal."),
        "input_schema": .object([
            "type": .string("object"),
            "properties": .object([
                "parentCardId": string("Optional topic card id to put these cards inside. Omit for the current portal."),
                "cards": .object([
                    "type": .string("array"),
                    "maxItems": .number(Double(maxCardsPerCall)),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": string("<= 60 characters"),
                            "summary": string("<= 140 characters, one or two short sentences"),
                            "body": string("Optional, <= 600 characters of extra detail shown when the card is opened"),
                            "type": .object(["type": .string("string"), "enum": .array([.string("topic"), .string("note")])]),
                            "isStub": .object(["type": .string("boolean"), "description": .string("true for an unexplored follow-up door")]),
                            "image": string("Optional short search phrase for a real picture that helps a kid picture this, e.g. 'Roman legionary armour' or 'Colosseum aerial'. Give one to every card."),
                            "sources": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
                                                "description": .string("URLs from this turn's web search that back this card")]),
                        ]),
                        "required": .array([.string("title"), .string("summary"), .string("isStub")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("cards")]),
        ]),
    ])

    public static let updateCard: JSONValue = .object([
        "name": .string("updateCard"),
        "description": .string("Change one of your own cards: fill a stub, fix text. Never the kid's cards."),
        "input_schema": .object([
            "type": .string("object"),
            "properties": .object([
                "cardId": string("Card id from the canvas summary"),
                "title": string("New title, <= 60 characters"),
                "summary": string("New summary, <= 140 characters"),
                "body": string("New detail, <= 600 characters"),
                "state": .object(["type": .string("string"), "enum": .array([.string("filled"), .string("stub")])]),
                "image": string("Optional short search phrase for a picture for this card"),
                "sources": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            ]),
            "required": .array([.string("cardId")]),
        ]),
    ])

    public static let suggestFocus: JSONValue = .object([
        "name": .string("suggestFocus"),
        "description": .string("Highlight a card the kid might want to look at next. Does not move their view."),
        "input_schema": .object([
            "type": .string("object"),
            "properties": .object([
                "cardId": string("Card id to highlight"),
                "reason": string("A few words shown to the kid, e.g. 'this is where it gets weird'"),
            ]),
            "required": .array([.string("cardId"), .string("reason")]),
        ]),
    ])

    public static let all = [createCards, updateCard, suggestFocus]
    /// The on-device model gets the minimum (plan §5.4).
    public static let reduced = [createCards, updateCard]

    // MARK: - Inputs

    public struct NewCard: Decodable, Equatable, Sendable {
        public var title: String
        public var summary: String
        public var body: String?
        public var type: CardType?
        public var isStub: Bool
        public var image: String?
        public var sources: [String]?
    }

    public struct CreateCards: Decodable, Equatable, Sendable {
        public var parentCardId: String?
        public var cards: [NewCard]
    }

    public struct UpdateCard: Decodable, Equatable, Sendable {
        public var cardId: String
        public var title: String?
        public var summary: String?
        public var body: String?
        public var state: CardState?
        public var image: String?
        public var sources: [String]?
    }

    public struct SuggestFocus: Decodable, Equatable, Sendable {
        public var cardId: String
        public var reason: String
    }

    /// Trim to a limit at a word boundary, with an ellipsis. Never fails the call over length.
    public static func clip(_ s: String, _ limit: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        let cut = t.prefix(limit - 1)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespaces) + "…"
    }
}
