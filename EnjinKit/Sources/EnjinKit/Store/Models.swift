import Foundation

public enum Author: String, Codable, Sendable { case kid, agent }

extension Date {
    /// Files store ISO-8601 with milliseconds; round so a save/load round trip is exact.
    public static var storeNow: Date { Date.now.roundedToMilliseconds }

    public var roundedToMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// A web page a card's claims came from (from the agent's web search).
public struct Source: Codable, Equatable, Sendable, Hashable {
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

/// Native source of truth for a card's meaning. Geometry lives in the portal's scene.
public struct StoredCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var portalId: String
    public var type: CardType
    public var title: String
    public var summary: String
    public var body: String?
    public var state: CardState
    public var createdBy: Author
    public var createdByTurnId: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Soft delete: set when the card's frame disappears from the canvas, cleared if it comes back (undo).
    public var deletedAt: Date?
    /// Optional so older files (without the key) still decode.
    public var sources: [Source]?
    /// Removed on purpose (undo of an agent turn). Unlike a canvas delete, a
    /// late canvas save that still shows the card must not bring it back.
    public var removed: Bool?

    public var isActive: Bool { deletedAt == nil }

    public init(id: String = "c-\(UUID().uuidString.lowercased())", portalId: String, type: CardType, title: String, summary: String,
                body: String? = nil, state: CardState, createdBy: Author, createdByTurnId: String? = nil, now: Date = .storeNow) {
        self.id = id; self.portalId = portalId; self.type = type; self.title = title; self.summary = summary; self.body = body
        self.state = state; self.createdBy = createdBy; self.createdByTurnId = createdByTurnId
        self.createdAt = now.roundedToMilliseconds; self.updatedAt = now.roundedToMilliseconds
    }
}

public struct Portal: Codable, Equatable, Sendable, Identifiable {
    public var portalId: String
    public var title: String
    /// The card you dive into to get here; nil for the notebook root.
    public var ownerCardId: String?
    public var parentPortalId: String?
    public var id: String { portalId }

    public init(portalId: String = "p-\(UUID().uuidString.lowercased())", title: String, ownerCardId: String?, parentPortalId: String?) {
        self.portalId = portalId; self.title = title; self.ownerCardId = ownerCardId; self.parentPortalId = parentPortalId
    }
}

public struct NotebookMeta: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var rootPortalId: String
    public var createdAt: Date
    public var updatedAt: Date
}

public struct NotebookData: Equatable, Sendable {
    public var meta: NotebookMeta
    public var cards: [StoredCard]
    public var portals: [Portal]

    public static func new(title: String, now: Date = .storeNow) -> NotebookData {
        let now = now.roundedToMilliseconds
        let root = Portal(title: title, ownerCardId: nil, parentPortalId: nil)
        return NotebookData(
            meta: NotebookMeta(id: "nb-\(UUID().uuidString.lowercased())", title: title, rootPortalId: root.portalId, createdAt: now, updatedAt: now),
            cards: [], portals: [root])
    }
}
