import Foundation

/// The hard-coded Roman Empire notebook used by the M0 spike. Same data and
/// portal rules as canvas-web's devHost (shared/demo-notebook.json).
/// Replaced by the file store in M1.
@MainActor
public final class DemoNotebook {
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

    private let file: File
    private var savedElements: [String: [JSONValue]] = [:]

    public var title: String { file.title }
    public var rootPortalId: String { file.rootPortalId }

    public init(data: Data) throws {
        file = try JSONDecoder().decode(File.self, from: data)
    }

    public func scene(for portalId: String) -> PortalScene? {
        guard let portal = file.portals.first(where: { $0.portalId == portalId }) else { return nil }
        var path: [Crumb] = []
        var cursor: File.Portal? = portal
        while let p = cursor {
            path.insert(Crumb(portalId: p.portalId, title: p.title), at: 0)
            cursor = file.portals.first { $0.portalId == p.parentPortalId }
        }
        let cards: [Card] = portal.cardIds.compactMap { id in
            guard let c = file.cards.first(where: { $0.id == id }) else { return nil }
            let childCount = file.portals.first { $0.ownerCardId == id }?.cardIds.count ?? 0
            return Card(id: c.id, type: c.type, title: c.title, summary: c.summary, state: c.state, childCount: childCount)
        }
        return PortalScene(portalId: portal.portalId, title: portal.title, path: path, cards: cards, elements: savedElements[portalId] ?? [])
    }

    /// Portal owned by `cardId`, if the card has been dived before.
    public func enter(cardId: String) -> PortalScene? {
        file.portals.first { $0.ownerCardId == cardId }.flatMap { scene(for: $0.portalId) }
    }

    /// Parent scene plus the card to frame on the way out, or nil at the root.
    public func exit(from portalId: String) -> (scene: PortalScene, focusCardId: String)? {
        guard let p = file.portals.first(where: { $0.portalId == portalId }),
              let parent = p.parentPortalId, let owner = p.ownerCardId,
              let scene = scene(for: parent) else { return nil }
        return (scene, owner)
    }

    public func ownerCardId(of portalId: String) -> String? {
        file.portals.first { $0.portalId == portalId }?.ownerCardId
    }

    public func save(portalId: String, elements: [JSONValue]) {
        savedElements[portalId] = elements
    }
}
