import Foundation

// Mirrors canvas-web/src/bridge/schema.ts. Keep in sync; ContractTests decode
// shared/bridge-fixtures to catch drift.

public let bridgeProtocolVersion = 1

// MARK: - Shared models

public enum CardType: String, Codable, Sendable { case topic, source, image, note }
public enum CardState: String, Codable, Sendable { case stub, filling, filled, error }

public struct CardImageRef: Codable, Equatable, Sendable {
    public var fileId: String
    public var width: Int
    public var height: Int
    public init(fileId: String, width: Int, height: Int) { self.fileId = fileId; self.width = width; self.height = height }
}

public struct Card: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: CardType
    public var title: String
    public var summary: String
    public var state: CardState
    public var childCount: Int
    public var image: CardImageRef?
    /// Reserve room for a picture that's still being found.
    public var imagePending: Bool?

    public init(id: String, type: CardType, title: String, summary: String, state: CardState, childCount: Int,
                image: CardImageRef? = nil, imagePending: Bool? = nil) {
        self.id = id; self.type = type; self.title = title; self.summary = summary; self.state = state; self.childCount = childCount
        self.image = image; self.imagePending = imagePending
    }
}

/// An image file for the canvas, as a data URL (Excalidraw's BinaryFileData).
public struct BridgeFile: Codable, Equatable, Sendable {
    public var id: String
    public var mimeType: String
    public var dataURL: String
    public init(id: String, mimeType: String, dataURL: String) { self.id = id; self.mimeType = mimeType; self.dataURL = dataURL }
}

public struct Crumb: Codable, Equatable, Sendable, Hashable {
    public var portalId: String
    public var title: String
}

public struct PortalScene: Codable, Equatable, Sendable {
    public var portalId: String
    public var title: String
    public var path: [Crumb]
    public var cards: [Card]
    public var elements: [JSONValue]
    /// Images the cards in this portal use.
    public var files: [BridgeFile]?
    /// The card this portal is inside: its picture as a banner, its summary under the title.
    public var hero: CardImageRef?
    public var subtitle: String?
}

public enum Transition: String, Codable, Sendable { case dive, exit, jump }

public enum CardOp: Codable, Equatable, Sendable {
    case upsert(Card)
    case delete(cardId: String)

    private enum CodingKeys: String, CodingKey { case op, card, cardId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .op) {
        case "upsert": self = .upsert(try c.decode(Card.self, forKey: .card))
        case "delete": self = .delete(cardId: try c.decode(String.self, forKey: .cardId))
        case let op: throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown op \(op)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsert(let card): try c.encode("upsert", forKey: .op); try c.encode(card, forKey: .card)
        case .delete(let id): try c.encode("delete", forKey: .op); try c.encode(id, forKey: .cardId)
        }
    }
}

public struct PlacedCard: Codable, Equatable, Sendable {
    public var cardId: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

// MARK: - Native -> Web

public enum NativeMethod {
    public struct PortalLoad: Codable, Sendable {
        public var scene: PortalScene
        public var transition: Transition
        public var focusCardId: String?
        public init(scene: PortalScene, transition: Transition, focusCardId: String? = nil) {
            self.scene = scene; self.transition = transition; self.focusCardId = focusCardId
        }
    }

    public struct InkLock: Codable, Sendable {
        public var locked: Bool
        public init(locked: Bool) { self.locked = locked }
    }

    public struct InkCommit: Codable, Sendable {
        public enum Tool: String, Codable, Sendable { case pen, highlighter }
        public var strokeId: String
        public var tool: Tool
        public var color: String
        public var width: Double
        /// WebView-local points in CSS px, as [x, y].
        public var points: [[Double]]
        /// 0...1, same count as points.
        public var pressures: [Double]
        public init(strokeId: String, tool: Tool, color: String, width: Double, points: [[Double]], pressures: [Double]) {
            self.strokeId = strokeId; self.tool = tool; self.color = color; self.width = width; self.points = points; self.pressures = pressures
        }
    }

    public struct InkCommitResult: Codable, Sendable {
        public var strokeId: String
        public var elementId: String
        public init(strokeId: String, elementId: String) { self.strokeId = strokeId; self.elementId = elementId }
    }

    public struct ApplyOps: Codable, Sendable {
        public var portalId: String
        public var ops: [CardOp]
        public init(portalId: String, ops: [CardOp]) { self.portalId = portalId; self.ops = ops }
    }

    public struct ApplyOpsResult: Codable, Sendable {
        public var placed: [PlacedCard]
    }

    public struct AddFiles: Codable, Sendable {
        public var files: [BridgeFile]
        public init(files: [BridgeFile]) { self.files = files }
    }

    public struct SetHeader: Codable, Sendable {
        public var portalId: String
        public var title: String
        public var subtitle: String?
        public var hero: CardImageRef?
        public init(portalId: String, title: String, subtitle: String?, hero: CardImageRef?) {
            self.portalId = portalId; self.title = title; self.subtitle = subtitle; self.hero = hero
        }
    }

    public struct SetBusy: Codable, Sendable {
        public var portalId: String
        /// Shown in an empty portal while Enjin fills it; nil hides it.
        public var message: String?
        public init(portalId: String, message: String?) { self.portalId = portalId; self.message = message }
    }

    public struct CanvasFrame: Codable, Sendable {
        public var cardId: String
        public init(cardId: String) { self.cardId = cardId }
    }

    public struct CanvasFrameResult: Codable, Sendable {
        public var framed: Bool
    }

    public struct CanvasFlash: Codable, Sendable {
        public var cardId: String
        public init(cardId: String) { self.cardId = cardId }
    }
}

// MARK: - Web -> Native

public enum WebMethod {
    public struct CanvasReady: Codable, Sendable {
        public var protocolVersion: Int
        public var excalidrawVersion: String
    }

    public struct CanvasReadyResult: Codable, Sendable {
        public var accepted: Bool
        public var reason: String?
        public init(accepted: Bool, reason: String? = nil) { self.accepted = accepted; self.reason = reason }
    }

    public struct CanvasChanged: Codable, Sendable {
        public var portalId: String
        public var elements: [JSONValue]
    }

    public struct FocusChanged: Codable, Sendable {
        public var portalId: String
        public var cardId: String?
        public var zoom: Double
        public var visibleCardIds: [String]
    }

    public struct CardOpen: Codable, Sendable {
        public var cardId: String
    }

    public struct SelectionChanged: Codable, Sendable {
        public var portalId: String
        public var cardIds: [String]
    }

    public struct PortalEnter: Codable, Sendable {
        public var portalId: String
        public var cardId: String
    }

    public struct PortalExit: Codable, Sendable {
        public var portalId: String
    }

    public struct PortalExitResult: Codable, Sendable {
        public var scene: PortalScene
        public var focusCardId: String
        public init(scene: PortalScene, focusCardId: String) { self.scene = scene; self.focusCardId = focusCardId }
    }

    public struct LogEvent: Codable, Sendable {
        public enum Level: String, Codable, Sendable { case debug, info, warn, error }
        public var level: Level
        public var message: String
        public var data: [String: JSONValue]?
    }
}

/// Encodes as JSON `null`, for notification results.
public struct Empty: Codable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encodeNil()
    }
}
