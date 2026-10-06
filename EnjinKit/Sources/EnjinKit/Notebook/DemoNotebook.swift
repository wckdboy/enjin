import Foundation

/// Builds a sample notebook from JSON (shared/sample-motors*.json is seeded on
/// first launch; shared/demo-notebook.json, Roman Empire, is the test fixture).
public enum DemoNotebook {
    struct File: Decodable {
        struct Portal: Decodable {
            var portalId: String
            var title: String
            var ownerCardId: String?
            var parentPortalId: String?
            var cardIds: [String]
        }
        struct RawCard: Decodable {
            var id: String
            var type: CardType
            var title: String
            var summary: String
            var state: CardState
            var body: String?
            var visual: Visual?
        }
        var title: String
        var rootPortalId: String
        var portals: [Portal]
        var cards: [RawCard]
    }

    public static func make(from data: Data, now: Date = .storeNow) throws -> NotebookData {
        let file = try JSONDecoder().decode(File.self, from: data)
        let portalOf = Dictionary(file.portals.flatMap { p in p.cardIds.map { ($0, p.portalId) } }, uniquingKeysWith: { a, _ in a })
        let cards = file.cards.compactMap { c -> StoredCard? in
            guard let portalId = portalOf[c.id] else { return nil }
            var card = StoredCard(id: c.id, portalId: portalId, type: c.type, title: c.title, summary: c.summary,
                                  body: c.body, state: c.state, createdBy: .agent, now: now)
            card.visual = c.visual
            return card
        }
        let portals = file.portals.map { Portal(portalId: $0.portalId, title: $0.title, ownerCardId: $0.ownerCardId, parentPortalId: $0.parentPortalId) }
        let meta = NotebookMeta(id: "nb-\(UUID().uuidString.lowercased())", title: file.title, rootPortalId: file.rootPortalId, createdAt: now, updatedAt: now)
        return NotebookData(meta: meta, cards: cards, portals: portals)
    }
}
