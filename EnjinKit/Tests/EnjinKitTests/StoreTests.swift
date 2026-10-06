import Foundation
import Testing
@testable import EnjinKit

func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("enjin-tests-\(UUID().uuidString)", isDirectory: true)
}

func demoData() throws -> NotebookData {
    let url = ContractTests.fixtures.deletingLastPathComponent().appendingPathComponent("demo-notebook.json")
    return try DemoNotebook.make(from: Data(contentsOf: url), now: Date(timeIntervalSince1970: 1_000_000))
}

struct StoreTests {
    @Test func roundTrip() async throws {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        try await store.saveScene(nb.meta.id, portalId: "p-root", elements: [.object(["id": .string("ink:1")])])

        #expect(try await store.load(nb.meta.id) == nb)
        #expect(try await store.scene(nb.meta.id, portalId: "p-root").count == 1)
        #expect(try await store.scene(nb.meta.id, portalId: "p-nope").isEmpty)
        #expect(await store.list().map(\.id) == [nb.meta.id])
    }

    @Test func listIsNewestFirstAndSkipsBrokenNotebooks() async throws {
        let root = tempRoot()
        let store = NotebookStore(root: root)
        var a = NotebookData.new(title: "A", now: Date(timeIntervalSince1970: 10))
        let b = NotebookData.new(title: "B", now: Date(timeIntervalSince1970: 20))
        try await store.save(a)
        try await store.save(b)
        a.meta.updatedAt = Date(timeIntervalSince1970: 30)
        try await store.saveMeta(a.meta)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("garbage"), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: root.appendingPathComponent("garbage/notebook.json"))
        #expect(await store.list().map(\.title) == ["A", "B"])
    }

    @Test func crashMidWriteLeavesOldFileIntact() async throws {
        let root = tempRoot()
        let store = NotebookStore(root: root)
        let nb = NotebookData.new(title: "Safe")
        try await store.save(nb)
        // Simulate a crash after the temp file was written but before rename.
        let tmp = root.appendingPathComponent("\(nb.meta.id)/.cards.json.DEAD.tmp")
        try Data("{\"half".utf8).write(to: tmp)
        #expect(try await store.load(nb.meta.id) == nb)
        #expect(!FileManager.default.fileExists(atPath: tmp.path), "stray temp files are cleaned up on load")
    }

    @Test func refusesNewerSchema() async throws {
        let root = tempRoot()
        try await NotebookStore(root: root, schemaVersion: 2).save(NotebookData.new(title: "Future"))
        let old = NotebookStore(root: root, schemaVersion: 1)
        let id = try #require(await NotebookStore(root: root, schemaVersion: 2).list().first?.id)
        await #expect(throws: StoreError.self) { try await old.load(id) }
    }

    @Test func migratesOlderSchemaWithBackup() async throws {
        let root = tempRoot()
        let nb = NotebookData.new(title: "Old")
        try await NotebookStore(root: root, schemaVersion: 1).save(nb)
        let migrated = NotebookStore(root: root, schemaVersion: 2, migrations: [
            1: { file, json in
                guard file == "notebook.json", case .object(var o) = json, case .object(var meta)? = o["notebook"] else { return json }
                meta["title"] = .string("Old (migrated)")
                o["notebook"] = .object(meta)
                return .object(o)
            },
        ])
        #expect(try await migrated.load(nb.meta.id).meta.title == "Old (migrated)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(nb.meta.id).backup-v1/notebook.json").path))
        #expect(await migrated.list().count == 1, "backups are not listed as notebooks")
    }
}

@MainActor
struct SessionTests {
    func session() async throws -> NotebookSession {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        return try await NotebookSession.open(nb.meta.id, store: store)
    }

    static func frame(_ cardId: String) -> JSONValue {
        .object(["id": .string("\(cardId):frame"), "customData": .object(["cardId": .string(cardId), "role": .string("frame")])])
    }

    @Test func divesThreeLevelsAndBack() async throws {
        let s = try await session()
        let root = try #require(try await s.scene(for: s.rootPortalId))
        #expect(root.cards.first { $0.id == "c-legions" }?.childCount == 3)
        _ = try #require(try await s.enter(cardId: "c-legions"))
        let whyWon = try #require(try await s.enter(cardId: "c-why-won"))
        let logistics = try #require(try await s.enter(cardId: "c-logistics"))
        #expect(logistics.path.map(\.title) == ["Roman Empire", "Legions", "Why Rome won so much", "Logistics"])
        let back = try #require(try await s.exit(from: logistics.portalId))
        #expect(back.scene.portalId == whyWon.portalId)
        #expect(back.focusCardId == "c-logistics")
        #expect(try await s.exit(from: s.rootPortalId) == nil)
    }

    @Test func firstDiveIntoAStubCreatesAPersistedPortal() async throws {
        let s = try await session()
        let scene = try #require(try await s.enter(cardId: "c-emperors"))
        #expect(scene.cards.isEmpty)
        #expect(scene.path.map(\.title) == ["Roman Empire", "Emperors"])
        let reloaded = try await s.store.load(s.id)
        #expect(reloaded.portals.contains { $0.ownerCardId == "c-emperors" })
        // Second dive reuses it.
        #expect(try await s.enter(cardId: "c-emperors")?.portalId == scene.portalId)
    }

    @Test func cardsDeletedOnCanvasAreSoftDeletedAndUndoRestoresThem() async throws {
        let s = try await session()
        let all = ["c-legions", "c-roads", "c-emperors", "c-fall"]
        var changed = try await s.saveElements(portalId: "p-root", elements: all.filter { $0 != "c-fall" }.map(Self.frame))
        #expect(changed == ["c-fall"])
        #expect(try await s.scene(for: "p-root")?.cards.map(\.id).contains("c-fall") == false)
        #expect(try await s.store.load(s.id).cards.first { $0.id == "c-fall" }?.deletedAt != nil)

        changed = try await s.saveElements(portalId: "p-root", elements: all.map(Self.frame))
        #expect(changed == ["c-fall"])
        #expect(s.card("c-fall")?.isActive == true)
    }

    @Test func createAndUpdateCardsPersist() async throws {
        let s = try await session()
        let c = try await s.createCard(in: "p-root", type: .note, title: "My idea", summary: "Rome had fast food", author: .kid)
        _ = try await s.updateCard("c-legions") { $0.title = "The Legions" }
        let reloaded = try await s.store.load(s.id)
        #expect(reloaded.cards.contains { $0.id == c.id && $0.createdBy == .kid })
        #expect(reloaded.cards.first { $0.id == "c-legions" }?.title == "The Legions")
        #expect(reloaded.portals.first { $0.ownerCardId == "c-legions" }?.title == "The Legions", "portal title follows its card")
        #expect(try await s.scene(for: "p-root")?.cards.contains { $0.id == c.id } == true)
    }
}

struct StoreDateTests {
    @Test func roundTripsExactlyForManyDates() {
        for _ in 0..<5_000 {
            let d = Date(timeIntervalSince1970: Double.random(in: -1e9...4e9)).roundedToMilliseconds
            #expect(StoreDate.parse(StoreDate.format(d)) == d)
        }
        #expect(StoreDate.format(Date(timeIntervalSince1970: 1.5)) == "1970-01-01T00:00:01.500Z")
        #expect(StoreDate.parse("2026-10-06T15:35:08Z") == Date(timeIntervalSince1970: 1_791_300_908))
    }
}
