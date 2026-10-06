import Foundation
import Testing
@testable import EnjinKit

@MainActor
struct DemoNotebookTests {
    static func notebook() throws -> DemoNotebook {
        let url = ContractTests.fixtures.deletingLastPathComponent().appendingPathComponent("demo-notebook.json")
        return try DemoNotebook(data: Data(contentsOf: url))
    }

    @Test func divesThreeLevelsAndBack() throws {
        let nb = try Self.notebook()
        let root = try #require(nb.scene(for: nb.rootPortalId))
        #expect(root.cards.first { $0.id == "c-legions" }?.childCount == 3)
        let legions = try #require(nb.enter(cardId: "c-legions"))
        let whyWon = try #require(nb.enter(cardId: "c-why-won"))
        let logistics = try #require(nb.enter(cardId: "c-logistics"))
        #expect(logistics.path.map(\.title) == ["Roman Empire", "Legions", "Why Rome won so much", "Logistics"])
        let back = try #require(nb.exit(from: logistics.portalId))
        #expect(back.scene.portalId == whyWon.portalId)
        #expect(back.focusCardId == "c-logistics")
        #expect(nb.exit(from: root.portalId) == nil)
        #expect(nb.enter(cardId: "c-roads") == nil)
        _ = legions
    }

    @Test func savedElementsComeBack() throws {
        let nb = try Self.notebook()
        nb.save(portalId: "p-legions", elements: [.object(["id": .string("ink:1")])])
        #expect(nb.scene(for: "p-legions")?.elements.count == 1)
    }
}
