import Foundation
import Testing
@testable import EnjinKit

@MainActor
struct GenerativeTests {
    let base = GuidanceTests()

    @Test func anIllustratePromptGetsArtMadeOnTheDeviceNotAPhoto() async throws {
        let (agent, _) = try await base.make([
            .init(calls: [createCards([
                .object(["title": .string("Inside a cell"), "summary": .string("x"), "isStub": .bool(false), "type": .string("topic"),
                         "illustrate": .string("cutaway of an animal cell, organelles glowing"), "image": .string("cell")]),
            ])]),
        ])
        agent.imageFinder = FakeFinder(answers: ["cell": ["https://c/1"]])
        agent.imageGenerator = FakeGenerator()
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        try await base.settle(agent)
        let card = try #require(agent.session.activeCards(in: "p-root").first { $0.title == "Inside a cell" })
        #expect(card.imagePrefer == .illustration)
        #expect(card.image?.kind == .illustration, "a topic would get a photo, but art was asked for")
        #expect(card.image?.sourceURL == "generated:cutaway of an animal cell, organelles glowing")
    }

    @Test func aNewNotebookGetsCoverArtForTheLibraryAndTheTopBanner() async throws {
        let (agent, canvas) = try await base.make([.init(calls: [createCards([card("Opener")])], text: "Go!")],
                                                  notebook: NotebookData.new(title: "Black holes"))
        agent.imageGenerator = FakeGenerator()
        agent.assist = FakeAssist()
        agent.begin(portalId: agent.session.rootPortalId)
        try await base.settle(agent)
        let cover = try #require(agent.session.data.meta.cover)
        #expect(cover.kind == .illustration)
        #expect(canvas.headers.last?.hero?.fileId == cover.fileId, "the top banner shows it at once")
        #expect(await agent.session.store.cover(agent.session.id) == Data("GEN".utf8), "the library cover uses it")
        #expect(try await agent.session.scene(for: agent.session.rootPortalId)?.hero?.fileId == cover.fileId, "and so does the next visit")
    }

    @Test func visualizeAsksForOneFigureCardBesideIt() async throws {
        let (agent, _) = try await base.make([.init(calls: [], text: "Here it is.")])
        agent.visualize(cardId: "c-roads", portalId: "p-root")
        try await base.settle(agent)
        let prompt = (agent.backend as! ScriptedBackend).prompts.first ?? ""
        #expect(prompt.contains("pressed Visualize on c-roads \"Roads\""))
        #expect(prompt.contains("ONE note card"))
    }

    @Test func graphRelationsMustJoinRealNodes() {
        let v = Visual(kind: .graph, items: [VisualItem(label: "Cas9"), VisualItem(label: "Guide RNA")],
                       links: [VisualLink(from: "guide rna", to: "Cas9", label: "steers"), VisualLink(from: "Cas9", to: "Ghost")]).sanitized()
        #expect(v?.links == [VisualLink(from: "guide rna", to: "Cas9", label: "steers")])
        let chart = Visual(kind: .chart, series: [VisualSeries(label: "a", points: [[1, 2], [3], [.nan, 1], [4, 5]])]).sanitized()
        #expect(chart?.series?.first?.points == [[1, 2], [4, 5]], "only finite pairs")
        #expect(chart?.plot == .line)
        #expect(Visual(kind: .table, columns: ["a"]).sanitized() == nil, "a table needs rows")
    }
}
