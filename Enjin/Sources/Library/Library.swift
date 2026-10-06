import EnjinKit
import Foundation
import UIKit
import Observation
import os

@MainActor
@Observable
final class Library {
    private(set) var notebooks: [NotebookMeta] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var counts: [String: Int] = [:]
    private(set) var error: String?
    let store: NotebookStore
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "library")

    init(store: NotebookStore) {
        self.store = store
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
            await loadCovers()
        } catch {
            log.error("library load failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func create(title: String, level: ExplorerLevel) async -> String? {
        let nb = NotebookData.new(title: title.isEmpty ? "Untitled" : title, level: level)
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
        await loadCovers()
    }

    private func loadCovers() async {
        for nb in notebooks {
            counts[nb.id] = await store.cardCount(nb.id)
            if let data = await store.cover(nb.id), let img = UIImage(data: data) { covers[nb.id] = img }
        }
    }
}
