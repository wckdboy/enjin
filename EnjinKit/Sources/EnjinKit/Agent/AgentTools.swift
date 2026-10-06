import Foundation

/// Client tool definitions and their validated inputs (plan §5.3).
public enum AgentTools {
    public static let maxCardsPerCall = 5
    public static let maxCardsPerTurn = 8
    public static let titleLimit = 60
    public static let summaryLimit = 140
    public static let bodyLimit = 900

    private static func string(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    /// A figure drawn on the card from structured data (no picture search needed).
    static let visual: JSONValue = .object([
        "type": .string("object"),
        "description": .string("""
        Optional figure drawn on the card, instead of a picture. Use one when structure explains better than words. \
        kind: flow (2-5 steps in order: items[].label + short detail), cycle (3-6 stages in a loop: items[].label, center), \
        timeline (2-6 events: items[].tag = when, label, detail), bars (2-6 numbers to compare: items[].label + value, one unit), \
        parts (what something is made of: center + 3-6 items[].label), stat (one striking number: value + unit), \
        formula (text like "F = m × a" + items[] as symbol legend: label = symbol, detail = meaning with unit), \
        code (text: up to 10 short lines of real code), live (html: an interactive model, see below), \
        graph (a concept map: items[].label = 3-8 nodes, links[] = {from, to, label} relations by node label, \
        e.g. "steers", "is made of", "causes"), table (compare things across properties: columns[] headers, rows[][] of \
        cells, first cell names the row; up to 5 x 6), chart (real data over a range: series[] = {label, points: [[x, y]]}, \
        up to 3 series and 40 points, plot line or scatter, xLabel, yLabel, logY for exponential growth). \
        Skills (put the data in spec): model3d, diorama, ui; see the spec field. \
        Labels <= 30 characters, details <= 48.
        """),
        "properties": .object([
            "kind": .object(["type": .string("string"), "enum": .array(VisualKind.allCases.map { .string($0.rawValue) })]),
            "items": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "label": .object(["type": .string("string")]),
                        "detail": .object(["type": .string("string")]),
                        "value": .object(["type": .string("number")]),
                        "tag": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("label")]),
                ]),
            ]),
            "center": .object(["type": .string("string")]),
            "value": .object(["type": .string("string"), "description": .string("stat: the number as written, e.g. \"299,792\"")]),
            "unit": .object(["type": .string("string")]),
            "text": .object(["type": .string("string"), "description": .string("formula expression or code")]),
            "links": .object(["type": .string("array"), "items": .object([
                "type": .string("object"),
                "properties": .object(["from": .object(["type": .string("string")]), "to": .object(["type": .string("string")]),
                                       "label": .object(["type": .string("string")])]),
                "required": .array([.string("from"), .string("to")]),
            ])]),
            "columns": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            "rows": .object(["type": .string("array"), "items": .object(["type": .string("array"), "items": .object(["type": .string("string")])])]),
            "series": .object(["type": .string("array"), "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "label": .object(["type": .string("string")]),
                    "points": .object(["type": .string("array"), "items": .object(["type": .string("array"), "items": .object(["type": .string("number")])])]),
                ]),
                "required": .array([.string("label"), .string("points")]),
            ])]),
            "plot": .object(["type": .string("string"), "enum": .array([.string("line"), .string("scatter")])]),
            "xLabel": .object(["type": .string("string")]),
            "yLabel": .object(["type": .string("string")]),
            "logY": .object(["type": .string("boolean")]),
            "spec": .object(["type": .string("object"), "description": .string("""
            For the skills (data, not code; ENJIN renders it):
            model3d: {"parts": [{"shape": "box|sphere|cylinder|cone|torus|ring|capsule|lathe|extrude|tube", "size": [w,h,d] (box), \
            "radius", "height", "tube" (torus), "inner" (ring), "profile": [[r,y],...] (lathe: bottles, bells, rocket bodies), \
            "outline": [[x,y],...] + "depth" (extrude: gears, wings, plates), "points": [[x,y,z],...] (tube: wires, pipes, struts), \
            "position": [x,y,z], "rotation": [deg,deg,deg], "color": "white|light|grey|dark|black|accent|glass|red|blue|green|yellow", \
            "label": "short name", "detail": "one sentence shown when tapped", "group": "name", "spin": {"axis": "x|y|z", "rpm"}, \
            "orbit": {"center": [x,y,z], "rpm"}, "explode": [dx,dy,dz] (where the part flies to in exploded view)}], \
            "groups": {"name": {"pivot": [x,y,z], "spin": {...}, "orbit": {...}}} (parts of an assembly that move together), \
            "atoms": [{"id", "element": "H|C|N|O|S|P|Cl|F|Na|Fe", "position": [x,y,z], "label", "detail"}], "bonds": [[id, id, order]] \
            (molecules, ball-and-stick, ~1.5 units per bond), "camera": {"azimuth", "elevation"}, "caption"}. Y is up; real \
            proportions; up to 80 parts. Label the parts that matter and give them a detail; animate what moves; add explode \
            offsets when the inside matters.
            diorama: {"layers": [{"depth": 0..1 (0 far, 1 near), "items": [...]}], "hotspots": [{"x","y","label","detail"}], \
            "steps": [{"label"}] (a scrubber through stages), "caption"}. The scene is 100 wide x 60 tall, y down. Items: \
            a prop from the library {"prop": "tree|pine|mountain|hill|cloud|sun|moon|planet|stars|waves|strata|house|building|\
            factory|turbine|volcano|cell|bacterium|atom|dna|rocket|satellite|person|car|fish|bird|plant|magnet|gear", "x", "y" \
            (where it stands), "s" (scale, ~10 units tall at 1; negative flips), "fill", "accent"}, or a shape {"shape": \
            "rect|circle|ellipse|path|text", "x","y","w","h","r","rx" or "d" (SVG path), "text", "size", "fill", "stroke", "opacity"}. \
            Fills: white|light|grey|dark|black|accent|sky|water|green|earth|red|blue|glass|none or #hex. Any item, layer or hotspot \
            can have "anim": "float|pulse|spin|drift" and "step": n (or "from"/"to") to appear only in those stages. 3-5 layers \
            from far (sky) to near (ground); props do most of the drawing. Give the card an illustrate prompt to paint a backdrop.
            ui: {"state": {"name": number}, "blocks": [...]} with blocks: {"type": "heading|text|callout", "text"} (text may embed \
            {{expr}} or {{expr|digits}}), {"type": "slider", "var", "min", "max", "step", "label", "unit"}, {"type": "toggle", \
            "var", "label"}, {"type": "choice", "var", "label", "options": [{"label", "value"}]}, {"type": "play", "var", "min", \
            "max", "seconds", "label", "loop", "autoplay"} (animates a variable: time, angle), {"type": "readout", "label", "expr", \
            "unit", "digits"}, {"type": "meter", "label", "expr", "max", "unit"}, {"type": "plot", "label", "expr" (in x and \
            state), "xmin", "xmax", "ymin", "ymax", "xLabel", "marker"}, {"type": "table", "label", "columns": [...], "rows": [[text \
            or {"expr", "unit", "digits"}]]}, {"type": "quiz", "question", "options": [...], "answer": index, "explain"}, {"type": \
            "answer", "question", "answer": expr, "tolerance": 0.05, "unit", "hint", "explain"} (work it out), {"type": "match", \
            "prompt", "pairs": [[term, meaning]]}, {"type": "steps", "items": [{"title", "text"}]}, {"type": "flashcards", \
            "cards": [{"front", "back"}]}, {"type": "order", "prompt", "items": [in the correct order]}, {"type": "row", \
            "blocks": [...]}. Expressions: + - * / % ^, comparisons, a ? b : c, pi, e, g, c, and sin cos tan sqrt abs exp ln log \
            min max pow round clamp. Make the explorer's choices change real numbers, and end with a check (quiz or answer).
            """)]),
            "html": .object(["type": .string("string"), "description": .string("""
            live only: one self-contained HTML snippet (markup, <style>, <script>; no <html>/<head>) under 20,000 characters. \
            It runs in a sandboxed iframe, about 650 x 380 px (read innerWidth/innerHeight, handle resize), with NO network: \
            no external scripts, fonts, images or fetch. Use canvas 2D or inline SVG and requestAnimationFrame. Touch input via \
            pointer events. Look (white, black, glass): background #ffffff, lines and type #0b0b0c, greys #66666b and \
            #e0e0de, black for what matters (a second colour, #e8590c, only if two things must be told apart); controls \
            are pill buttons (#f4f4f3, 0.75px #e0e0de edge; the main one solid #0b0b0c with white text) and sliders in a \
            row at the bottom; a monospace readout of the live numbers. It must start moving on its own and show \
            the idea with no instructions; controls let the explorer change one or two variables and see the effect.
            """)]),
        ]),
        "required": .array([.string("kind")]),
    ])

    public static let createCards: JSONValue = .object([
        "name": .string("createCards"),
        "description": .string("Add up to 5 cards to the canvas. They go into the portal the kid is looking at, or inside parentCardId's portal."),
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
                            "body": string("<= 900 characters of real depth shown when the card is opened: how it works, why, numbers, a surprising detail. Give one to every filled card."),
                            "type": .object(["type": .string("string"), "enum": .array([.string("topic"), .string("note")])]),
                            "isStub": .object(["type": .string("boolean"), "description": .string("true for an unexplored follow-up door")]),
                            "image": string("Short search phrase for a real picture that helps a kid picture this, e.g. 'Mars Curiosity rover selfie' or 'neuron microscope'. Give one to every card without a visual."),
                            "illustrate": string("Instead of image: a prompt for an illustration made on the device, for what no photo can show (inside a cell, a machine cutaway, a black hole up close, a future robot). Describe subject, viewpoint and setting; no words in the picture."),
                            "visual": visual,
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
                "body": string("New detail, <= 900 characters"),
                "state": .object(["type": .string("string"), "enum": .array([.string("filled"), .string("stub")])]),
                "image": string("Optional short search phrase for a picture for this card"),
                "illustrate": string("Optional prompt for an illustration made on the device instead of a photo"),
                "visual": visual,
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
        public var visual: Visual?
        public var illustrate: String?

        private enum CodingKeys: String, CodingKey { case title, summary, body, type, isStub, image, sources, visual, illustrate }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
            body = try c.decodeIfPresent(String.self, forKey: .body)
            type = try? c.decodeIfPresent(CardType.self, forKey: .type)
            isStub = (try? c.decodeIfPresent(Bool.self, forKey: .isStub)) ?? false
            image = try c.decodeIfPresent(String.self, forKey: .image)
            sources = try? c.decodeIfPresent([String].self, forKey: .sources)
            illustrate = try? c.decodeIfPresent(String.self, forKey: .illustrate)
            // A figure the canvas can't draw is dropped, never the whole card.
            visual = (try? c.decodeIfPresent(Visual.self, forKey: .visual))?.sanitized()
        }
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
        public var visual: Visual?
        public var illustrate: String?

        private enum CodingKeys: String, CodingKey { case cardId, title, summary, body, state, image, sources, visual, illustrate }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cardId = try c.decode(String.self, forKey: .cardId)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            summary = try c.decodeIfPresent(String.self, forKey: .summary)
            body = try c.decodeIfPresent(String.self, forKey: .body)
            state = try? c.decodeIfPresent(CardState.self, forKey: .state)
            image = try c.decodeIfPresent(String.self, forKey: .image)
            sources = try? c.decodeIfPresent([String].self, forKey: .sources)
            visual = (try? c.decodeIfPresent(Visual.self, forKey: .visual))?.sanitized()
            illustrate = try? c.decodeIfPresent(String.self, forKey: .illustrate)
        }
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
