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

/// A picture on a card. Bytes live in the notebook's files/ folder.
public struct CardImage: Codable, Equatable, Sendable {
    public var fileId: String
    public var mimeType: String
    public var width: Int
    public var height: Int
    /// Attribution shown in the card's detail sheet, e.g. "Jane Doe · CC BY-SA 4.0".
    public var credit: String?
    /// Where the picture came from (its Wikimedia Commons page).
    public var sourceURL: String?
    /// Photo or on-device illustration (nil in older notebooks: photo).
    public var kind: PictureKind?

    public init(fileId: String, mimeType: String, width: Int, height: Int, credit: String? = nil, sourceURL: String? = nil) {
        self.fileId = fileId; self.mimeType = mimeType; self.width = width; self.height = height; self.credit = credit; self.sourceURL = sourceURL
    }
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
    public var image: CardImage?
    /// A picture is being looked for with this phrase; cleared when found or given up.
    public var imageQuery: String?
    /// A figure drawn on the card instead of a picture.
    public var visual: Visual?
    /// What kind of picture the agent asked for (nil: decided by the card, see PicturePipeline).
    public var imagePrefer: PictureKind?
    /// Placed by hand in the world (sketches, and what grew from them).
    public var place: CardPlace?
    /// The explorer's own drawing (its picture is the ink).
    public var sketch: Bool?

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
    /// Cover art for the library and the top-level banner (generated when the notebook begins).
    public var cover: CardImage?
    /// How deep the explorer wants to go; every turn is pitched at it (nil in older notebooks: student).
    public var level: ExplorerLevel?
}

/// How deep and technical Enjin goes, chosen by the explorer for each notebook.
public enum ExplorerLevel: String, Codable, Sendable, CaseIterable {
    /// Big ideas, vivid examples, few terms.
    case curious
    /// Real mechanisms, key terms, numbers, simple formulas and code.
    case student
    /// University level: precise terms, equations, real data, research.
    case expert
}

public struct NotebookData: Equatable, Sendable {
    public var meta: NotebookMeta
    public var cards: [StoredCard]
    public var portals: [Portal]

    public static func new(title: String, level: ExplorerLevel? = nil, now: Date = .storeNow) -> NotebookData {
        let now = now.roundedToMilliseconds
        let root = Portal(title: title, ownerCardId: nil, parentPortalId: nil)
        var meta = NotebookMeta(id: "nb-\(UUID().uuidString.lowercased())", title: title, rootPortalId: root.portalId, createdAt: now, updatedAt: now)
        meta.level = level
        return NotebookData(meta: meta, cards: [], portals: [root])
    }
}
