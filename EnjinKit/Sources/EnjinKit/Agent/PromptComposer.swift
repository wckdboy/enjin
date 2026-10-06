import Foundation

/// Builds the per-turn user message: what's on the canvas, where the explorer is,
/// what they changed, and what they asked (plan §5.2). Pure apart from reading
/// the session, so it's golden-testable.
@MainActor
public enum PromptComposer {
    public enum Request: Equatable, Sendable {
        /// The explorer typed something.
        case ask(String)
        /// The explorer dived into a stub (or we're prefetching it): fill it.
        case fill(cardId: String)
        /// A brand-new notebook: open it up with a first set of cards.
        case begin
        /// The explorer dived into a filled topic that is empty inside: build the next level down.
        case expand(cardId: String)
        /// The explorer asked to see a card's idea as a visual.
        case visualize(cardId: String)
    }

    /// A finished turn elsewhere, carried into other portals' prompts as text.
    public struct TailEntry: Equatable, Sendable {
        public var portalTitle: String
        public var kidSaid: String
        public var cardsMade: [String]
        public init(portalTitle: String, kidSaid: String, cardsMade: [String]) {
            self.portalTitle = portalTitle; self.kidSaid = kidSaid; self.cardsMade = cardsMade
        }
    }

    /// Rough budget in characters (~4 chars per token).
    public static let defaultBudgetChars = 12_000 * 4

    public static func compose(session: NotebookSession, portalId: String, focusCardId: String?, request: Request,
                               changes: [NotebookSession.KidChange], tail: [TailEntry],
                               budgetChars: Int = defaultBudgetChars, compact: Bool = false, language: AppLanguage = .en) -> String {
        // Tiers from the inside out; outer tiers are dropped first when over budget.
        let here = currentPortal(session, portalId, focusCardId, compact: compact)
        let around = compact ? "" : surroundings(session, portalId)
        let elsewhere = compact ? "" : distant(session, portalId)
        let changeText = changesText(session, changes, portalId)
        let tailText = compact ? "" : tailText(tail)
        var ask = requestText(session, request)
        if language != .en {
            // Per turn (not in the cached system prompt), so switching language takes effect at once.
            ask += "\n\nLanguage: write your reply and every card's title, summary and body in \(language.promptName). Keep image phrases in English (they search English Wikipedia)."
        }

        var parts = [here, around, elsewhere, changeText, tailText, ask]
        // Drop: elsewhere, then tail, then surroundings. "Here", changes and the ask always stay.
        for drop in [2, 4, 1] where parts.joined().count > budgetChars { parts[drop] = "" }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // MARK: - Tiers

    static func cardLine(_ session: NotebookSession, _ c: StoredCard, detail: Bool) -> String {
        var line = "- \(c.id) · \(c.type.rawValue) · \(c.state.rawValue)\(c.createdBy == .kid ? " · made by the explorer" : "") · \"\(c.title)\""
        if detail, !c.summary.isEmpty, c.state != .stub { line += ": \(c.summary)" }
        if let inside = session.childPortal(of: c.id) {
            let n = session.activeCards(in: inside.portalId).count
            if n > 0 { line += " (\(n) cards inside)" }
        }
        return line
    }

    static func currentPortal(_ session: NotebookSession, _ portalId: String, _ focusCardId: String?, compact: Bool) -> String {
        let path = session.path(to: portalId).map(\.title).joined(separator: " › ")
        var lines = ["<canvas notebook=\"\(session.title)\">", "The explorer is looking at: \(path)"]
        if let owner = session.ownerCardId(of: portalId).flatMap(session.card) {
            lines.append("This portal is inside the card \(owner.id) \"\(owner.title)\"\(owner.summary.isEmpty ? "" : ": \(owner.summary)")")
        }
        let cards = session.activeCards(in: portalId)
        lines.append(cards.isEmpty ? "No cards here yet." : "Cards here:")
        lines += cards.map { cardLine(session, $0, detail: !compact) }
        if let focus = focusCardId.flatMap(session.card), focus.isActive {
            lines.append("Closest to the center of their screen: \(focus.id) \"\(focus.title)\"")
        }
        let marks = session.marks(in: portalId)
        var made: [String] = []
        if marks.inkStrokes > 0 { made.append("\(marks.inkStrokes) pencil stroke\(marks.inkStrokes == 1 ? "" : "s")") }
        if marks.shapes > 0 { made.append("\(marks.shapes) shape\(marks.shapes == 1 ? "" : "s")") }
        if !marks.notes.isEmpty { made.append("notes: " + marks.notes.prefix(5).map { "\"\(String($0.prefix(80)))\"" }.joined(separator: ", ")) }
        if !made.isEmpty { lines.append("The explorer's own marks here: " + made.joined(separator: "; ")) }
        lines.append("</canvas>")
        return lines.joined(separator: "\n")
    }

    static func surroundings(_ session: NotebookSession, _ portalId: String) -> String {
        guard let parent = session.portal(portalId)?.parentPortalId, let parentPortal = session.portal(parent) else { return "" }
        let owner = session.ownerCardId(of: portalId)
        let siblings = session.activeCards(in: parent).map { $0.id == owner ? "\($0.title) (here)" : $0.title }
        return "<around>\nOne level up, \"\(parentPortal.title)\" has: \(siblings.joined(separator: ", "))\n</around>"
    }

    static func distant(_ session: NotebookSession, _ portalId: String) -> String {
        let near = Set([portalId, session.portal(portalId)?.parentPortalId].compactMap { $0 })
        let others = session.data.portals.filter { !near.contains($0.portalId) }
        let counts = others.map { ($0.title, session.activeCards(in: $0.portalId).count) }.filter { $0.1 > 0 }
        guard !counts.isEmpty else { return "" }
        return "<elsewhere>\n" + counts.map { "\($0.0): \($0.1) cards" }.joined(separator: "; ") + "\n</elsewhere>"
    }

    static func changesText(_ session: NotebookSession, _ changes: [NotebookSession.KidChange], _ portalId: String) -> String {
        guard !changes.isEmpty else { return "" }
        let lines = changes.map { c -> String in
            let whereText = c.portalId == portalId ? "" : " (in \"\(session.portal(c.portalId)?.title ?? "another portal")\")"
            switch c.kind {
            case .createdCard(let t): return "- made a card \"\(t)\"\(whereText)"
            case .editedCard(let t): return "- edited their card \"\(t)\"\(whereText)"
            case .deletedCard(let t, let byAgent): return "- deleted \(byAgent ? "your" : "their") card \"\(t)\"\(whereText)"
            case .restoredCard(let t): return "- brought back the card \"\(t)\"\(whereText)"
            case .drew(let n): return "- drew \(n) pencil stroke\(n == 1 ? "" : "s")\(whereText)"
            case .wroteNote(let t): return "- wrote \"\(String(t.prefix(80)))\"\(whereText)"
            }
        }
        return "<since_last_time>\n" + lines.joined(separator: "\n") + "\n</since_last_time>"
    }

    static func tailText(_ tail: [TailEntry]) -> String {
        guard !tail.isEmpty else { return "" }
        let lines = tail.map { t in
            "- In \"\(t.portalTitle)\" the explorer said \"\(String(t.kidSaid.prefix(120)))\"" + (t.cardsMade.isEmpty ? "" : "; you made: \(t.cardsMade.joined(separator: ", "))")
        }
        return "<earlier_elsewhere>\n" + lines.joined(separator: "\n") + "\n</earlier_elsewhere>"
    }

    static func requestText(_ session: NotebookSession, _ request: Request) -> String {
        switch request {
        case .ask(let text):
            return "The explorer says: \(text)"
        case .begin:
            return """
            The explorer just started a new notebook about "\(session.title)". Open it up: one short, excited sentence, \
            then createCards with 3-4 filled topic cards that show how this really works (each with a body and an image \
            phrase), one note card with a visual (the key process, parts, numbers or formula), and 2 stubs (with image \
            phrases) as doors to explore. Concrete, accurate, surprising.
            """
        case .visualize(let cardId):
            let c = session.card(cardId)
            return """
            The explorer pressed Visualize on \(cardId) "\(c?.title ?? "")"\(c.map { $0.summary.isEmpty ? "" : ": \($0.summary)" } ?? "")\
            \(c?.body.map { " (detail: \(String($0.prefix(400))))" } ?? ""). Show this idea visually: createCards with ONE note card \
            in this portal whose visual explains it best. Choose the form: a live model if moving and touching it teaches most \
            (a mechanism, a system with a variable, an algorithm), otherwise the right figure (flow, cycle, chart, table, graph, \
            parts, formula, code, timeline, bars, stat). Title it after what it shows; the summary says what to notice. \
            Accuracy first. Keep your reply to one short sentence.
            """
        case .expand(let cardId):
            let c = session.card(cardId)
            return """
            The explorer dived into \(cardId) "\(c?.title ?? "")"\(c.map { $0.summary.isEmpty ? "" : " (\($0.summary))" } ?? ""), \
            and it's empty inside. Build the next level down: createCards with parentCardId \(cardId) (4-5 cards that go deeper \
            than the card itself: the mechanism, the parts, real numbers, an example; filled cards with bodies, at least one with \
            a visual, and 2 stubs). Don't change the card itself. Keep your reply to one short sentence.
            """
        case .fill(let cardId):
            let c = session.card(cardId)
            return """
            The explorer dived into the stub card \(cardId) "\(c?.title ?? "")"\(c.map { $0.summary.isEmpty ? "" : " (\($0.summary))" } ?? ""). \
            Fill it: updateCard \(cardId) with a real summary, a body and state "filled", then createCards with parentCardId \(cardId) \
            (3-5 cards: filled cards with bodies, at least one with a visual, and 2 stubs). Keep your reply to one short sentence.
            """
        }
    }
}
