import EnjinKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class Library {
    private(set) var notebooks: [NotebookMeta] = []
    private(set) var error: String?
    let store: NotebookStore
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "library")

    init(store: NotebookStore) {
        self.store = store
    }

    /// First launch: seed the Roman Empire sample so there is something to explore.
    func load() async {
        do {
            notebooks = await store.list()
            if notebooks.isEmpty, let url = Bundle.main.url(forResource: "demo-notebook", withExtension: "json") {
                try await store.save(DemoNotebook.make(from: Data(contentsOf: url)))
                notebooks = await store.list()
            }
        } catch {
            log.error("library load failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func create(title: String) async -> String? {
        let nb = NotebookData.new(title: title.isEmpty ? "Untitled" : title)
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
    }

    func refresh() async {
        notebooks = await store.list()
    }
}
