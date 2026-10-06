import Foundation
import Testing
@testable import EnjinKit

struct VisualTests {
    private func newCard(_ json: String) throws -> AgentTools.NewCard {
        try JSONDecoder().decode(AgentTools.NewCard.self, from: Data(json.utf8))
    }

    @Test func numbersWrittenAsStringsStillBecomeBars() throws {
        let c = try newCard("""
        {"title": "Compute", "summary": "s", "isStub": false,
         "visual": {"kind": "bars", "unit": "GFLOPS", "items": [{"label": "Phone", "value": "2,000"}, {"label": "PC", "value": 80000}]}}
        """)
        #expect(c.visual?.items?.map(\.value) == [2000, 80000])
    }

    @Test func aFigureTheCanvasCantDrawIsDroppedNotTheCard() throws {
        let unknown = try newCard(#"{"title": "T", "summary": "s", "isStub": false, "visual": {"kind": "hologram"}}"#)
        #expect(unknown.title == "T" && unknown.visual == nil)
        let empty = try newCard(#"{"title": "T", "summary": "s", "isStub": false, "visual": {"kind": "stat"}}"#)
        #expect(empty.visual == nil, "a stat needs a value")
        let oneBar = try newCard(#"{"title": "T", "summary": "s", "isStub": false, "visual": {"kind": "bars", "items": [{"label": "a", "value": 1}]}}"#)
        #expect(oneBar.visual == nil, "nothing to compare")
    }

    @Test func sanitizingKeepsFiguresDrawable() {
        let steps = (1...8).map { VisualItem(label: "Step \($0) " + String(repeating: "x", count: 40), detail: String(repeating: "d", count: 90)) }
        let v = Visual(kind: .flow, items: steps).sanitized()
        #expect(v?.items?.count == 5)
        #expect(v?.items?.allSatisfy { $0.label.count <= 30 && ($0.detail?.count ?? 0) <= 48 } == true)
        let code = Visual(kind: .code, text: (1...14).map { "line \($0) " + String(repeating: "y", count: 80) }.joined(separator: "\n")).sanitized()
        #expect(code?.text?.split(separator: "\n").count == 10)
        #expect(code?.text?.split(separator: "\n").allSatisfy { $0.count <= 64 } == true)
    }

    @MainActor @Test func aCardWithAFigurePersistsAndSkipsThePictureSearch() async throws {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let s = try await NotebookSession.open(nb.meta.id, store: store)
        let v = Visual(kind: .formula, items: [VisualItem(label: "F", detail: "force")], text: "F = m × a")
        let c = try await s.createCard(in: "p-root", type: .note, title: "Newton", summary: "Push", author: .agent, imageQuery: "apple", visual: v)
        #expect(c.imageQuery == nil)
        let bridged = s.bridgeCard(c)
        #expect(bridged.visual == v && bridged.imagePending == nil)
        let reloaded = try await store.load(s.id)
        #expect(reloaded.cards.first { $0.id == c.id }?.visual == v)
    }
}

struct SampleNotebookTests {
    @Test(arguments: ["sample-motors.json", "sample-motors.da.json"])
    func theSampleLoadsWithDrawableFiguresAndDepth(_ name: String) throws {
        let url = ContractTests.fixtures.deletingLastPathComponent().appendingPathComponent(name)
        let nb = try DemoNotebook.make(from: Data(contentsOf: url))
        let figures = nb.cards.compactMap(\.visual)
        #expect(Set(figures.map(\.kind)) == Set(VisualKind.allCases.filter { $0 != .cycle }), "shows off the figure kinds")
        for v in figures { #expect(v.sanitized() == v, "\(v.kind) is drawable as written") }
        #expect(nb.cards.filter { $0.type == .topic && $0.state == .filled }.allSatisfy { ($0.body ?? "").count > 200 }, "filled topics have depth")
        #expect(nb.portals.count == 5)
    }
}
