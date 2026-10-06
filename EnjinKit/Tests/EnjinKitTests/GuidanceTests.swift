import Foundation
import Testing
@testable import EnjinKit

struct FakeAssist: AssistHelper {
    func nextQuestions(path: [String], cards: [(title: String, summary: String)], lastAsk: String?) async -> [String] {
        ["Did they have horses?", "Who led them?", "Third one"]
    }
    func imagePhrase(title: String, summary: String, topic: String) async -> String? { "phrase for \(title)" }
}

struct FakeGenerator: ImageGenerator {
    func generate(_ prompt: String) async -> FoundImage? {
        FoundImage(data: Data("GEN".utf8), mimeType: "image/png", width: 512, height: 512, credit: nil, sourceURL: "generated:\(prompt)")
    }
}

/// Marks the data so tests can see it went through the stylizer.
struct MarkStylizer: ImageStylizer {
    func stylize(_ image: FoundImage) async -> FoundImage {
        var i = image
        i.data = Data("STYLED-".utf8) + image.data
        return i
    }
}

@MainActor
struct GuidanceTests {
    func make(_ steps: [ScriptedBackend.Step], notebook: NotebookData? = nil) async throws -> (AgentSession, FakeCanvas) {
        let store = NotebookStore(root: tempRoot())
        let nb = try notebook ?? demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        _ = try await session.scene(for: nb.meta.rootPortalId)
        let agent = AgentSession(session: session, backend: ScriptedBackend(steps), telemetry: nil)
        let canvas = FakeCanvas()
        agent.canvas = canvas
        return (agent, canvas)
    }

    func settle(_ agent: AgentSession) async throws {
        for _ in 0..<500 where agent.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(60))
    }

    @Test func afterATurnTheKidGetsDiveAndQuestionChips() async throws {
        let (agent, _) = try await make([
            .init(calls: [createCards([card("Fact"), card("Door one", stub: true), card("Door two", stub: true), card("Door three", stub: true)])], text: "ok"),
        ])
        agent.assist = FakeAssist()
        agent.ask("tell me", portalId: "p-root", focusCardId: nil)
        try await settle(agent)
        let dives = agent.nextSteps.compactMap { if case .dive(_, let t) = $0 { t } else { nil } }
        let asks = agent.nextSteps.compactMap { if case .ask(let q) = $0 { q } else { nil } }
        #expect(dives == ["Door one", "Door two"])
        #expect(asks == ["Did they have horses?", "Who led them?"])
    }

    @Test func aNewNotebookBeginsItselfWithABusyHint() async throws {
        let (agent, canvas) = try await make([.init(calls: [createCards([card("Opener")])], text: "Let's go!")],
                                             notebook: NotebookData.new(title: "Volcanoes"))
        let root = agent.session.rootPortalId
        agent.begin(portalId: root)
        try await settle(agent)
        #expect(agent.session.activeCards(in: root).map(\.title) == ["Opener"])
        #expect(canvas.busy.first?.1 == "Enjin is exploring Volcanoes…")
        #expect(canvas.busy.last?.1 == nil, "the hint goes away")
        let prompt = (agent.backend as! ScriptedBackend).prompts.first ?? ""
        #expect(prompt.contains("just started a new notebook about \"Volcanoes\""))
    }

    @Test func stubsPreferIllustrationsFactsPreferPhotosAndEverythingIsStyled() async throws {
        let (agent, _) = try await make([
            .init(calls: [createCards([
                .object(["title": .string("Fact"), "summary": .string("x"), "isStub": .bool(false), "image": .string("legion")]),
                .object(["title": .string("Door"), "summary": .string("y"), "isStub": .bool(true)]),
            ])]),
        ])
        agent.imageFinder = FakeFinder(answers: ["legion": ["https://c/1"], "phrase for Door": ["https://c/2"]])
        agent.imageGenerator = FakeGenerator()
        agent.imageStylizer = MarkStylizer()
        agent.assist = FakeAssist()
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        try await settle(agent)
        let cards = agent.session.activeCards(in: "p-root").filter { $0.createdByTurnId != nil }
        let fact = try #require(cards.first { $0.title == "Fact" })
        let door = try #require(cards.first { $0.title == "Door" })
        #expect(fact.image?.kind == .photo)
        #expect(door.image?.kind == .illustration, "stubs get illustrations")
        #expect(door.image?.sourceURL == "generated:phrase for Door", "phrase came from the on-device helper")
        let data = try #require(await agent.session.store.file(agent.session.id, fileId: fact.image!.fileId))
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("STYLED-"))
    }

    @Test func kidCardsGetPicturesToo() async throws {
        let (agent, canvas) = try await make([])
        agent.imageGenerator = FakeGenerator()
        agent.assist = FakeAssist()
        let mine = try await agent.session.createCard(in: "p-root", type: .note, title: "Pizza", summary: "did they eat pizza", author: .kid)
        await agent.decorateKidCard(mine.id)
        try await Task.sleep(for: .milliseconds(60))
        #expect(agent.session.card(mine.id)?.image?.kind == .illustration)
        #expect(canvas.files.count == 1)
    }

    @Test func fillingAStubUpdatesThePortalHeader() async throws {
        let (agent, canvas) = try await make([
            .init(calls: [("updateCard", .object(["cardId": .string("c-emperors"), "summary": .string("70+ emperors."), "state": .string("filled")]))]),
        ])
        _ = try await agent.session.ensurePortal(for: "c-emperors")
        agent.fill(cardId: "c-emperors")
        try await settle(agent)
        #expect(canvas.headers.last?.subtitle == "70+ emperors.")
        #expect(canvas.headers.last?.title == "Emperors")
    }

    @Test func prefetchIsOffUnlessAParentTurnsItOn() async throws {
        let (agent, _) = try await make([.init(text: "x")])
        agent.prefetch(cardId: "c-fall")
        try await Task.sleep(for: .milliseconds(30))
        #expect((agent.backend as! ScriptedBackend).prompts.isEmpty)
    }
}
