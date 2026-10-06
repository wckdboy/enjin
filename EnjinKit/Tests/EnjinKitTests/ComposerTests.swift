import Foundation
import Testing
@testable import EnjinKit

@MainActor
struct ComposerTests {
    static let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden")

    /// Compare against a checked-in file; on mismatch write `.actual` next to it for review.
    func expectGolden(_ name: String, _ text: String) throws {
        let url = Self.golden.appendingPathComponent(name)
        guard let want = try? String(contentsOf: url, encoding: .utf8) else {
            try text.write(to: url, atomically: true, encoding: .utf8)
            Issue.record("wrote new golden \(name); review and re-run")
            return
        }
        if want != text { try text.write(to: url.appendingPathExtension("actual"), atomically: true, encoding: .utf8) }
        #expect(want == text, "golden \(name) differs; see \(name).actual")
    }

    func session() async throws -> NotebookSession {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        return try await NotebookSession.open(nb.meta.id, store: store)
    }

    @Test func askInsideLegions() async throws {
        let s = try await session()
        _ = try await s.scene(for: "p-legions")
        try await s.saveElements(portalId: "p-legions", elements: [
            SessionTests.frame("c-why-won"), SessionTests.frame("c-equipment"),
            .object(["type": .string("freedraw"), "id": .string("ink1")]),
            .object(["type": .string("text"), "id": .string("t1"), "text": .string("testudo??")]),
        ])
        let text = PromptComposer.compose(
            session: s, portalId: "p-legions", focusCardId: "c-why-won", request: .ask("why did they always win?"),
            changes: s.drainChangeLog(), tail: [.init(portalTitle: "Roads", kidSaid: "how long were they", cardsMade: ["Via Appia"])])
        try expectGolden("ask-legions.txt", text)
    }

    @Test func fillStub() async throws {
        let s = try await session()
        let p = try #require(try await s.ensurePortal(for: "c-emperors"))
        let text = PromptComposer.compose(session: s, portalId: p.portalId, focusCardId: nil, request: .fill(cardId: "c-emperors"), changes: [], tail: [])
        try expectGolden("fill-emperors.txt", text)
    }

    @Test func compactPromptForOnDeviceModelIsSmall() async throws {
        let s = try await session()
        let full = PromptComposer.compose(session: s, portalId: "p-legions", focusCardId: nil, request: .ask("hi"), changes: [], tail: [])
        let compact = PromptComposer.compose(session: s, portalId: "p-legions", focusCardId: nil, request: .ask("hi"), changes: [], tail: [], compact: true)
        #expect(compact.count < full.count)
        #expect(!compact.contains("<elsewhere>"))
        #expect(compact.contains("c-why-won"))
    }

    @Test func bigNotebookStaysInBudgetAndKeepsTheCurrentPortal() async throws {
        let store = NotebookStore(root: tempRoot())
        var nb = NotebookData.new(title: "Big")
        for i in 0..<20 {
            let owner = StoredCard(id: "c-\(i)", portalId: nb.meta.rootPortalId, type: .topic, title: "Topic \(i)", summary: String(repeating: "word ", count: 25), state: .filled, createdBy: .agent)
            nb.cards.append(owner)
            let p = Portal(portalId: "p-\(i)", title: "Topic \(i)", ownerCardId: owner.id, parentPortalId: nb.meta.rootPortalId)
            nb.portals.append(p)
            for j in 0..<15 {
                nb.cards.append(StoredCard(id: "c-\(i)-\(j)", portalId: p.portalId, type: .topic, title: "Card \(i).\(j)", summary: String(repeating: "detail ", count: 18), state: .filled, createdBy: .agent))
            }
        }
        try await store.save(nb)
        let s = try await NotebookSession.open(nb.meta.id, store: store)
        let budget = 6_000
        let text = PromptComposer.compose(session: s, portalId: "p-3", focusCardId: nil, request: .ask("more"), changes: [], tail: [], budgetChars: budget)
        #expect(text.count <= budget)
        #expect(text.contains("c-3-14"), "every card in the current portal is listed")
        #expect(text.contains("The kid says: more"))
    }
}
