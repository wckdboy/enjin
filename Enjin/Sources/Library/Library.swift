import EnjinKit
import Foundation
import UIKit
import Observation
import os

/// Something the explorer made themselves (a card, a note, a sketch), wherever it lives.
struct ExplorerNote: Identifiable, Equatable {
    var id: String { cardId }
    let notebookId: String
    let notebookTitle: String
    let portalId: String
    let portalTitle: String
    let cardId: String
    let title: String
    let summary: String
    let sketch: Bool
    let createdAt: Date
    var thumbnail: UIImage?
}

/// What the home screen shows: every world, how big it is, where you were, and your own notes across all of them.
@MainActor
@Observable
final class Library {
    private(set) var notebooks: [NotebookMeta] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var counts: [String: Int] = [:]
    /// Portals (levels) explored in each world.
    private(set) var depths: [String: Int] = [:]
    /// Where "jump back in" lands: the title of the portal you were last in.
    private(set) var lastPlace: [String: String] = [:]
    private(set) var notes: [ExplorerNote] = []
    private(set) var error: String?
    let store: NotebookStore
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "library")

    init(store: NotebookStore) {
        self.store = store
    }

    /// The explorer's own shelves, from the worlds in them (A to Z).
    var collections: [String] {
        Array(Set(notebooks.compactMap(\.collection))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The world they were in most recently.
    var latest: NotebookMeta? {
        notebooks.max { ($0.openedAt ?? $0.updatedAt) < ($1.openedAt ?? $1.updatedAt) }
    }

    /// Every notebook is generated live by Enjin from what the explorer picks; nothing
    /// is pre-built. (Debug builds can seed a hand-made sample for tests and screenshots
    /// with `-seedSample`.)
    func load(language: AppLanguage) async {
        do {
            notebooks = await store.list()
            #if DEBUG
            let name = language == .da ? "sample-motors.da" : "sample-motors"
            if notebooks.isEmpty, ProcessInfo.processInfo.arguments.contains("-seedSample"),
               let url = Bundle.main.url(forResource: name, withExtension: "json") {
                try await store.save(DemoNotebook.make(from: Data(contentsOf: url)))
                notebooks = await store.list()
            }
            #endif
            await loadDetails()
        } catch {
            log.error("library load failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func create(title: String, level: ExplorerLevel, collection: String? = nil) async -> String? {
        var nb = NotebookData.new(title: title.isEmpty ? "Untitled" : title, level: level)
        nb.meta.collection = collection
        do {
            try await store.save(nb)
            notebooks = await store.list()
            return nb.meta.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func delete(_ id: String) async {
        do {
            try await store.delete(id)
        } catch {
            self.error = error.localizedDescription
        }
        notebooks = await store.list()
        notes.removeAll { $0.notebookId == id }
    }

    func refresh() async {
        notebooks = await store.list()
        await loadDetails()
    }

    // MARK: - Organizing

    func setPinned(_ id: String, _ pinned: Bool) async {
        await changeMeta(id) { $0.pinned = pinned ? true : nil }
    }

    /// Move a world to a shelf (nil: no shelf).
    func move(_ id: String, to collection: String?) async {
        let name = collection?.trimmingCharacters(in: .whitespacesAndNewlines)
        await changeMeta(id) { $0.collection = name?.isEmpty == false ? name : nil }
    }

    func renameCollection(_ old: String, to new: String) async {
        for nb in notebooks where nb.collection == old { await move(nb.id, to: new) }
    }

    func rename(_ id: String, to title: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, var data = try? await store.load(id) else { return }
        data.meta.title = t
        if let i = data.portals.firstIndex(where: { $0.portalId == data.meta.rootPortalId }) { data.portals[i].title = t }
        do {
            try await store.save(data)
        } catch {
            self.error = error.localizedDescription
        }
        notebooks = await store.list()
    }

    private func changeMeta(_ id: String, _ change: (inout NotebookMeta) -> Void) async {
        guard var meta = notebooks.first(where: { $0.id == id }) else { return }
        change(&meta)
        do {
            try await store.saveMeta(meta)
        } catch {
            self.error = error.localizedDescription
        }
        notebooks = await store.list()
    }

    /// Worlds and notes matching a search (titles, and what's inside: card titles and summaries).
    func matches(_ query: String) -> (worlds: Set<String>, notes: [ExplorerNote]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return (Set(notebooks.map(\.id)), notes) }
        let worlds = Set(notebooks.filter { $0.title.localizedCaseInsensitiveContains(q) || ($0.collection ?? "").localizedCaseInsensitiveContains(q) }.map(\.id))
            .union(searchIndex.filter { $0.value.contains { $0.localizedCaseInsensitiveContains(q) } }.map(\.key))
        let found = notes.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q) }
        return (worlds, found)
    }

    // MARK: - Loading

    @ObservationIgnored private var searchIndex: [String: [String]] = [:]

    private func loadDetails() async {
        var all: [ExplorerNote] = []
        for nb in notebooks {
            counts[nb.id] = await store.cardCount(nb.id)
            if let data = await store.cover(nb.id), let img = UIImage(data: data) { covers[nb.id] = img }
            guard let data = try? await store.load(nb.id) else { continue }
            let active = data.cards.filter { $0.deletedAt == nil && $0.removed != true }
            depths[nb.id] = data.portals.filter { p in active.contains { $0.portalId == p.portalId } }.count
            searchIndex[nb.id] = active.flatMap { [$0.title, $0.summary] }
            let portals = Dictionary(uniqueKeysWithValues: data.portals.map { ($0.portalId, $0.title) })
            if let last = nb.lastPortalId, last != nb.rootPortalId, let title = portals[last] { lastPlace[nb.id] = title } else { lastPlace[nb.id] = nil }
            for c in active where c.createdBy == .kid {
                var note = ExplorerNote(notebookId: nb.id, notebookTitle: nb.title, portalId: c.portalId, portalTitle: portals[c.portalId] ?? nb.title,
                                        cardId: c.id, title: c.title, summary: c.summary, sketch: c.sketch == true, createdAt: c.createdAt)
                if c.sketch == true, let image = c.image, let bytes = await store.file(nb.id, fileId: image.fileId) {
                    note.thumbnail = UIImage(data: bytes)?.preparingThumbnail(of: CGSize(width: 360, height: 240))
                }
                all.append(note)
            }
        }
        notes = all.sorted { $0.createdAt > $1.createdAt }
    }
}
