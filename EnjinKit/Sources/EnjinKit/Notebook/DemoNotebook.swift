import Foundation

/// Builds the Roman Empire sample notebook from shared/demo-notebook.json.
/// Seeded into the store on first launch so there is something to explore.
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
            return StoredCard(id: c.id, portalId: portalId, type: c.type, title: c.title, summary: c.summary,
                              state: c.state, createdBy: .agent, now: now)
        }
        let portals = file.portals.map { Portal(portalId: $0.portalId, title: $0.title, ownerCardId: $0.ownerCardId, parentPortalId: $0.parentPortalId) }
        let meta = NotebookMeta(id: "nb-\(UUID().uuidString.lowercased())", title: file.title, rootPortalId: file.rootPortalId, createdAt: now, updatedAt: now)
        return NotebookData(meta: meta, cards: cards, portals: portals)
    }
}
