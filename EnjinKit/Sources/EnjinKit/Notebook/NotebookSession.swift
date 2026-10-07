import Foundation

/// One open notebook: portal navigation, card changes, and persistence.
/// Every mutation is written through to the store before it returns.
@MainActor
public final class NotebookSession {
    public private(set) var data: NotebookData
    public let store: NotebookStore
    private var scenes: [String: [JSONValue]] = [:]
    private var fileCache: [String: BridgeFile] = [:]
    private let clock: @Sendable () -> Date

    /// What the kid did since the agent last looked (plan §5.2 #4). Capped; the agent drains it.
    public private(set) var changeLog: [KidChange] = []
    public static let changeLogCap = 10

    public struct KidChange: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case createdCard(title: String)
            case editedCard(title: String)
            case deletedCard(title: String, byAgent: Bool)
            case restoredCard(title: String)
            case drew(strokes: Int)
            case wroteNote(String)
        }
        public var portalId: String
        public var kind: Kind
    }

    /// Kid marks on a portal's canvas that aren't cards, for the scene summary.
    public struct Marks: Equatable, Sendable {
        public var inkStrokes = 0
        public var notes: [String] = []
        public var shapes = 0
    }

    public var id: String { data.meta.id }
    public var title: String { data.meta.title }
    public var rootPortalId: String { data.meta.rootPortalId }

    public init(data: NotebookData, store: NotebookStore, clock: @escaping @Sendable () -> Date = { .storeNow }) {
        self.data = data
        self.store = store
        self.clock = clock
    }

    public static func open(_ id: String, store: NotebookStore) async throws -> NotebookSession {
        NotebookSession(data: try await store.load(id), store: store)
    }

    // MARK: - Reading

    public func portal(_ portalId: String) -> Portal? {
        data.portals.first { $0.portalId == portalId }
    }

    public func activeCards(in portalId: String) -> [StoredCard] {
        data.cards.filter { $0.portalId == portalId && $0.isActive }
    }

    public func card(_ id: String) -> StoredCard? {
        data.cards.first { $0.id == id }
    }

    public func ownerCardId(of portalId: String) -> String? {
        portal(portalId)?.ownerCardId
    }

    public func path(to portalId: String) -> [Crumb] {
        var path: [Crumb] = []
        var cursor = portal(portalId)
        while let p = cursor {
            path.insert(Crumb(portalId: p.portalId, title: p.title), at: 0)
            cursor = p.parentPortalId.flatMap(portal)
        }
        return path
    }

    public func childPortal(of cardId: String) -> Portal? {
        data.portals.first { $0.ownerCardId == cardId }
    }

    public func marks(in portalId: String) -> Marks {
        Self.marks(scenes[portalId] ?? [])
    }

    static func marks(_ elements: [JSONValue]) -> Marks {
        var m = Marks()
        for e in elements where e["isDeleted"] != .bool(true) && e["customData"]?["role"] == nil {
            switch e["type"]?.stringValue {
            case "freedraw": m.inkStrokes += 1
            case "text": if let t = e["text"]?.stringValue, !t.isEmpty { m.notes.append(t) }
            case "rectangle", "ellipse", "diamond", "arrow", "line": m.shapes += 1
            default: break
            }
        }
        return m
    }

    /// Hand the agent what changed and start a fresh log.
    public func drainChangeLog() -> [KidChange] {
        defer { changeLog = [] }
        return changeLog
    }

    private func logChange(_ c: KidChange) {
        changeLog.append(c)
        if changeLog.count > Self.changeLogCap { changeLog.removeFirst(changeLog.count - Self.changeLogCap) }
    }

    public func bridgeCard(_ c: StoredCard) -> Card {
        let childCount = data.portals.first { $0.ownerCardId == c.id }.map { activeCards(in: $0.portalId).count } ?? 0
        return Card(id: c.id, type: c.type, title: c.title, summary: c.summary, state: c.state, childCount: childCount,
                    image: c.image.map { CardImageRef(fileId: $0.fileId, width: $0.width, height: $0.height) },
                    imagePending: c.visual == nil && c.image == nil && c.imageQuery != nil ? true : nil, visual: c.visual)
    }

    /// Header for the portal inside `cardId` (if it has one).
    public func header(forPortalOf cardId: String) -> NativeMethod.SetHeader? {
        guard let p = childPortal(of: cardId), let c = card(cardId) else { return nil }
        return NativeMethod.SetHeader(portalId: p.portalId, title: p.title, subtitle: c.summary.isEmpty ? nil : c.summary,
                                      hero: c.image.map { CardImageRef(fileId: $0.fileId, width: $0.width, height: $0.height) })
    }

    /// The image file for the canvas, from cache or disk.
    public func bridgeFile(_ image: CardImage) async -> BridgeFile? {
        if let f = fileCache[image.fileId] { return f }
        guard let data = await store.file(id, fileId: image.fileId) else { return nil }
        let f = BridgeFile(id: image.fileId, mimeType: image.mimeType, dataURL: "data:\(image.mimeType);base64,\(data.base64EncodedString())")
        fileCache[image.fileId] = f
        return f
    }

    public func files(in portalId: String) async -> [BridgeFile] {
        var out: [BridgeFile] = []
        for c in activeCards(in: portalId) {
            if let img = c.image, let f = await bridgeFile(img) { out.append(f) }
        }
        return out
    }

    /// Store a found picture and put it on the card.
    public func attachImage(_ cardId: String, data bytes: Data, image: CardImage) async throws -> StoredCard? {
        try await store.saveFile(id, fileId: image.fileId, data: bytes)
        fileCache[image.fileId] = BridgeFile(id: image.fileId, mimeType: image.mimeType,
                                             dataURL: "data:\(image.mimeType);base64,\(bytes.base64EncodedString())")
        return try await updateCard(cardId, by: .agent) {
            $0.image = image
            $0.imageQuery = nil
        }
    }

    /// Give the notebook its cover art. Returns the top level's new header.
    public func attachCover(data bytes: Data, image: CardImage) async throws -> NativeMethod.SetHeader {
        try await store.saveFile(id, fileId: image.fileId, data: bytes)
        fileCache[image.fileId] = BridgeFile(id: image.fileId, mimeType: image.mimeType,
                                             dataURL: "data:\(image.mimeType);base64,\(bytes.base64EncodedString())")
        data.meta.cover = image
        try await touch()
        return NativeMethod.SetHeader(portalId: rootPortalId, title: portal(rootPortalId)?.title ?? title, subtitle: nil,
                                      hero: CardImageRef(fileId: image.fileId, width: image.width, height: image.height))
    }

    /// Picture URLs already used in this notebook, so cards don't repeat each other.
    public var usedImageSources: Set<String> {
        Set(data.cards.compactMap { $0.image?.sourceURL })
    }

    public func scene(for portalId: String) async throws -> PortalScene? {
        guard let p = portal(portalId) else { return nil }
        let elements: [JSONValue]
        if let cached = scenes[portalId] {
            elements = cached
        } else {
            elements = try await store.scene(id, portalId: portalId)
            scenes[portalId] = elements
        }
        var files = await files(in: portalId)
        let owner = p.ownerCardId.flatMap(card)
        // The top level's banner is the notebook's cover art; a portal's is its card's picture.
        let banner = owner?.image ?? (portalId == rootPortalId ? data.meta.cover : nil)
        if let img = banner, let f = await bridgeFile(img) { files.append(f) }
        return PortalScene(portalId: p.portalId, title: p.title, path: path(to: portalId),
                           cards: activeCards(in: portalId).map(bridgeCard), elements: elements, files: files.isEmpty ? nil : files,
                           hero: banner.map { CardImageRef(fileId: $0.fileId, width: $0.width, height: $0.height) },
                           subtitle: owner.flatMap { $0.summary.isEmpty ? nil : $0.summary })
    }

    // MARK: - Navigation

    /// Dive into a topic card. The first dive creates the card's portal.
    public func enter(cardId: String) async throws -> PortalScene? {
        guard let portal = try await ensurePortal(for: cardId) else { return nil }
        return try await scene(for: portal.portalId)
    }

    /// The portal inside a topic card, created on first use.
    public func ensurePortal(for cardId: String) async throws -> Portal? {
        guard let card = card(cardId), card.isActive, card.type == .topic else { return nil }
        if let existing = childPortal(of: cardId) { return existing }
        let portal = Portal(title: card.title, ownerCardId: card.id, parentPortalId: card.portalId)
        data.portals.append(portal)
        try await store.savePortals(id, data.portals)
        try await touch()
        return portal
    }

    /// What's inside a topic, without going in (nil if it has never been opened).
    public func peek(cardId: String) async throws -> PortalScene? {
        guard let portal = childPortal(of: cardId) else { return nil }
        return try await scene(for: portal.portalId)
    }

    /// Go inside something the explorer zoomed into: a topic card as it is, anything else
    /// (a part of a model, a panel) as a topic of its own, found by title or made as a stub to fill.
    public func zoomInto(portalId: String, title: String, detail: String?, cardId: String?) async throws -> (scene: PortalScene, cardId: String)? {
        if let cardId, let c = card(cardId), c.isActive, c.type == .topic, let scene = try await enter(cardId: cardId) {
            return (scene, cardId)
        }
        let name = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty, portal(portalId) != nil else { return nil }
        let existing = activeCards(in: portalId).first { $0.type == .topic && $0.title.caseInsensitiveCompare(name) == .orderedSame }
        let topic: StoredCard
        if let existing { topic = existing } else {
            topic = try await createCard(in: portalId, type: .topic, title: name, summary: detail ?? "", state: .stub, author: .kid)
        }
        guard let scene = try await enter(cardId: topic.id) else { return nil }
        return (scene, topic.id)
    }

    public func exit(from portalId: String) async throws -> (scene: PortalScene, focusCardId: String)? {
        guard let p = portal(portalId), let parent = p.parentPortalId, let owner = p.ownerCardId,
              let scene = try await scene(for: parent) else { return nil }
        return (scene, owner)
    }

    // MARK: - Writing

    /// Persist a portal's canvas and reconcile card existence with it: a card
    /// whose frame is gone was deleted on the canvas; one whose frame came back was undone.
    /// Returns ids of cards whose deleted state changed.
    @discardableResult
    public func saveElements(portalId: String, elements: [JSONValue]) async throws -> [String] {
        let before = scenes[portalId].map(Self.marks)
        scenes[portalId] = elements
        if let before {
            let after = Self.marks(elements)
            if after.inkStrokes > before.inkStrokes { logChange(.init(portalId: portalId, kind: .drew(strokes: after.inkStrokes - before.inkStrokes))) }
            for note in after.notes where !before.notes.contains(note) { logChange(.init(portalId: portalId, kind: .wroteNote(note))) }
        }
        try await store.saveScene(id, portalId: portalId, elements: elements)

        let framed = Set(elements.compactMap { e -> String? in
            guard e["customData"]?["role"]?.stringValue == "frame", e["isDeleted"] != .bool(true) else { return nil }
            return e["customData"]?["cardId"]?.stringValue
        })
        var changed: [String] = []
        let now = clock()
        for i in data.cards.indices where data.cards[i].portalId == portalId {
            let present = framed.contains(data.cards[i].id)
            if data.cards[i].isActive && !present {
                data.cards[i].deletedAt = now
                changed.append(data.cards[i].id)
                logChange(.init(portalId: portalId, kind: .deletedCard(title: data.cards[i].title, byAgent: data.cards[i].createdBy == .agent)))
            } else if !data.cards[i].isActive && present && data.cards[i].removed != true {
                data.cards[i].deletedAt = nil
                changed.append(data.cards[i].id)
                logChange(.init(portalId: portalId, kind: .restoredCard(title: data.cards[i].title)))
            }
        }
        if !changed.isEmpty { try await store.saveCards(id, data.cards) }
        try await touch()
        return changed
    }

    public func createCard(id cardId: String? = nil, in portalId: String, type: CardType, title: String, summary: String, body: String? = nil,
                           state: CardState = .filled, author: Author, turnId: String? = nil, sources: [Source]? = nil,
                           imageQuery: String? = nil, visual: Visual? = nil, imagePrefer: PictureKind? = nil) async throws -> StoredCard {
        var card = StoredCard(portalId: portalId, type: type, title: title, summary: summary, body: body, state: state,
                              createdBy: author, createdByTurnId: turnId, now: clock())
        if let cardId { card.id = cardId }
        card.sources = sources
        // Figures replace pictures, except a diorama, whose backdrop is a picture.
        card.imageQuery = visual == nil || visual?.kind == .diorama ? imageQuery : nil
        card.visual = visual
        card.imagePrefer = imagePrefer
        data.cards.append(card)
        if author == .kid { logChange(.init(portalId: portalId, kind: .createdCard(title: title))) }
        try await store.saveCards(id, data.cards)
        try await touch()
        return card
    }

    public func updateCard(_ cardId: String, by author: Author = .kid, _ change: (inout StoredCard) -> Void) async throws -> StoredCard? {
        guard let i = data.cards.firstIndex(where: { $0.id == cardId }) else { return nil }
        change(&data.cards[i])
        if author == .kid { logChange(.init(portalId: data.cards[i].portalId, kind: .editedCard(title: data.cards[i].title))) }
        data.cards[i].updatedAt = clock()
        // Keep a portal's title in step with the card it belongs to.
        if let p = data.portals.firstIndex(where: { $0.ownerCardId == cardId }), data.portals[p].title != data.cards[i].title {
            data.portals[p].title = data.cards[i].title
            try await store.savePortals(id, data.portals)
        }
        try await store.saveCards(id, data.cards)
        try await touch()
        return data.cards[i]
    }

    /// Soft-delete (agent undo). The canvas is told separately via applyOps.
    public func deleteCard(_ cardId: String) async throws {
        guard let i = data.cards.firstIndex(where: { $0.id == cardId }) else { return }
        data.cards[i].deletedAt = clock()
        data.cards[i].removed = true
        try await store.saveCards(id, data.cards)
        try await touch()
    }

    /// Put back an exact earlier version of a card (agent undo of an update).
    public func restore(_ card: StoredCard) async throws {
        guard let i = data.cards.firstIndex(where: { $0.id == card.id }) else { return }
        data.cards[i] = card
        if let p = data.portals.firstIndex(where: { $0.ownerCardId == card.id }) { data.portals[p].title = card.title }
        try await store.saveCards(id, data.cards)
        try await store.savePortals(id, data.portals)
        try await touch()
    }

    public func rename(_ title: String) async throws {
        data.meta.title = title
        if let i = data.portals.firstIndex(where: { $0.portalId == rootPortalId }) { data.portals[i].title = title }
        try await store.savePortals(id, data.portals)
        try await touch()
    }

    private func touch() async throws {
        data.meta.updatedAt = clock()
        try await store.saveMeta(data.meta)
    }
}
