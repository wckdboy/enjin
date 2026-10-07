import Foundation
import Testing
@testable import EnjinKit

/// Enjin as a learning partner: User.md, noticing what the explorer does, chiming in.
@MainActor
struct PartnerTests {
    func make(_ steps: [ScriptedBackend.Step]) async throws -> (AgentSession, ScriptedBackend, FakeCanvas) {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        _ = try await session.scene(for: "p-root")
        let backend = ScriptedBackend(steps)
        let agent = AgentSession(session: session, backend: backend, telemetry: Telemetry(url: tempRoot().appendingPathComponent("t.jsonl")))
        let canvas = FakeCanvas()
        agent.canvas = canvas
        return (agent, backend, canvas)
    }

    func waitIdle(_ agent: AgentSession) async {
        for _ in 0..<1000 where agent.isRunning { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - User.md

    @Test func userMdKeepsNotesBySectionAndSurvivesARoundTrip() throws {
        let url = tempRoot().appendingPathComponent("User.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let p = LearnerProfile(url: url)
        #expect(p.isEmpty)
        #expect(p.promptText.contains("still getting to know them"))
        p.remember("Learns fastest by dragging a slider and watching", in: .learning)
        p.remember("3D models over diagrams", in: .visuals)
        p.remember("3D models over diagrams", in: .visuals) // no duplicates
        #expect(p.notes(in: .visuals) == ["3D models over diagrams"])
        // Replaced when it's no longer true.
        p.remember("3D models, and charts once there are numbers", in: .visuals, replacing: "3D models over diagrams")
        #expect(p.notes(in: .visuals) == ["3D models, and charts once there are numbers"])
        #expect(p.markdown.contains("## How I learn best\n- Learns fastest by dragging a slider and watching"))

        let again = LearnerProfile(url: url)
        #expect(again.notes(in: .learning) == ["Learns fastest by dragging a slider and watching"])
        #expect(again.promptText.contains("## Visuals that work for me"))
        #expect(!again.promptText.contains("What doesn't work")) // empty sections stay out of the prompt
    }

    @Test func userMdCapsEachSectionAndAcceptsHandEdits() {
        let p = LearnerProfile(url: nil)
        for i in 1...12 { p.remember("note \(i)", in: .curious) }
        #expect(p.notes(in: .curious).count == LearnerProfile.maxNotesPerSection)
        #expect(p.notes(in: .curious).first == "note 5") // oldest make room
        p.replace(with: "## Level and pace\n- Wants to go faster\nnot a bullet but kept\n## Nonsense\n- ignored")
        #expect(p.notes(in: .level) == ["Wants to go faster", "not a bullet but kept"])
        #expect(p.notes(in: .curious).isEmpty)
        p.reset()
        #expect(p.isEmpty)
    }

    // MARK: - Attention

    @Test func attentionSummarisesWhatTheyDidInPlainWords() {
        let log = AttentionLog()
        log.record([
            .init(kind: .look, cardId: "c-legions", ms: 6000),
            .init(kind: .look, cardId: "c-legions", ms: 3000),
            .init(kind: .tap, label: "Shield"),
            .init(kind: .explode),
            .init(kind: .play, cardId: "c-roads", ms: 12000),
            .init(kind: .look, cardId: "c-roads", ms: 900), // too short to mention as a look
        ], in: "p-root")
        let text = log.summary { ["c-legions": "Legions", "c-roads": "Roads"][$0] } ?? ""
        #expect(text.contains("looked at \"Legions\" for 9s"))
        #expect(text.contains("tapped the part \"Shield\""))
        #expect(text.contains("pulled the model apart"))
        #expect(text.contains("played with \"Roads\" for 12s"))
        #expect(!text.contains("looked at \"Roads\""))
        let best = log.strongestInterest(since: nil, in: "p-root")
        #expect(best?.event.cardId == "c-roads" && best?.ms == 12900)
    }

    // MARK: - Companion

    @Test func companionChimesInOnceAboutWhatTheyDwellOnThenBacksOff() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let (agent, backend, _) = try await make([.init(text: "Watch the shields overlap."), .init(text: ""), .init(text: "")])
        let log = AttentionLog { now }
        agent.attention = log
        agent.clock = { now }
        let companion = Companion(agent: agent, attention: log) { now }

        // A glance isn't interest.
        log.record([.init(kind: .look, cardId: "c-legions", ms: 3000)], in: "p-root")
        #expect(companion.consider(portalId: "p-root") == nil)
        // Lingering is.
        now += 10
        log.record([.init(kind: .look, cardId: "c-legions", ms: 6000)], in: "p-root")
        let said = companion.consider(portalId: "p-root")
        #expect(said?.contains("\"Legions\"") == true)
        await waitIdle(agent)
        #expect(agent.reply == "Watch the shields overlap.")
        #expect(backend.prompts.first?.contains("Nobody asked: you noticed something") == true)
        #expect(backend.prompts.first?.contains("looked at \"Legions\" for 9s") == true)
        #expect(agent.status == .idle) // a nudge never shows a working state

        // Not the same thing twice, and not right after Enjin spoke.
        now += 5
        log.record([.init(kind: .look, cardId: "c-legions", ms: 9000)], in: "p-root")
        #expect(companion.consider(portalId: "p-root") == nil)

        // Something new: they didn't answer the first nudge, so it waits twice the gap (90 s), then yes.
        now += 60
        log.record([.init(kind: .look, cardId: "c-roads", ms: 9000)], in: "p-root")
        #expect(companion.consider(portalId: "p-root") == nil)
        now += 40
        #expect(companion.consider(portalId: "p-root") != nil)
        await waitIdle(agent)
        #expect(companion.ignored == 1)
        now += 100 // past the doubled gap, inside the quadrupled one (two ignored in a row)
        log.record([.init(kind: .play, cardId: "c-why-won", ms: 9000)], in: "p-root")
        #expect(companion.consider(portalId: "p-root") == nil)
        // They talk to Enjin: engaged again, back to normal.
        companion.explorerSpoke()
        #expect(companion.ignored == 0)
        #expect(companion.consider(portalId: "p-root") != nil)
    }

    @Test func companionStaysQuietWhileTypingOrWhenTurnedOff() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let (agent, _, _) = try await make([])
        let log = AttentionLog { now }
        log.record([.init(kind: .look, cardId: "c-legions", ms: 20000)], in: "p-root")
        let companion = Companion(agent: agent, attention: log) { now }
        #expect(companion.consider(portalId: "p-root", typing: true) == nil)
        companion.enabled = false
        #expect(companion.consider(portalId: "p-root") == nil)
    }

    // MARK: - Tools

    @Test func enjinAsksWithTappableAnswersAndTheAnswerComesBack() async throws {
        let (agent, backend, _) = try await make([
            .init(calls: [("askLearner", .object(["question": .string("What do you think happens if the shields gap?"),
                                                  "choices": .array([.string("Arrows get in"), .string("Nothing"), .string("They run")])]))],
                  text: "Quick guess first."),
            .init(text: "Exactly."),
        ])
        agent.ask("how did the testudo work?", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(agent.question == .init(text: "What do you think happens if the shields gap?", choices: ["Arrows get in", "Nothing", "They run"]))
        agent.answer("Arrows get in", portalId: "p-root", focusCardId: nil)
        #expect(agent.question == nil)
        await waitIdle(agent)
        #expect(backend.prompts.last?.contains("(answering your question \"What do you think happens if the shields gap?\") Arrows get in") == true)
    }

    @Test func enjinWritesWhatItLearnsToUserMdAndReadsItEveryTurn() async throws {
        let (agent, backend, _) = try await make([
            .init(calls: [("rememberAboutLearner", .object(["section": .string("Visuals that work for me"), "note": .string("Turns every 3D model around before reading")]))]),
            .init(text: "ok"),
        ])
        let profile = LearnerProfile(url: nil)
        agent.learner = profile
        agent.ask("show me the engine", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(profile.notes(in: .visuals) == ["Turns every 3D model around before reading"])
        agent.ask("and the gearbox?", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(backend.prompts.last?.contains("<learner file=\"User.md\">") == true)
        #expect(backend.prompts.last?.contains("Turns every 3D model around before reading") == true)
    }

    // MARK: - Cost

    @Test func nudgesRunOnTheLightModelInTheirOwnSmallContext() async throws {
        let (agent, main, _) = try await make([])
        let light = ScriptedBackend([.init(calls: [createCards([card("Nope")])], text: "See the overlap?")])
        agent.lightBackend = light
        agent.nudge("They've been looking at \"Legions\" for 12 seconds.", portalId: "p-root", focusCardId: "c-legions")
        await waitIdle(agent)
        #expect(main.prompts.isEmpty, "the main model isn't used for a nudge")
        #expect(light.prompts.count == 1)
        #expect(light.threadLengths == [1], "a fresh one-message context, not the portal's thread")
        #expect(agent.reply == "See the overlap?")
        // A nudge can't build; making cards is a real turn.
        #expect(agent.session.activeCards(in: "p-root").filter { $0.createdByTurnId != nil }.isEmpty)
    }

    @Test func aCardsBodyIsWrittenWhenItsOpenedOnTheLightModel() async throws {
        let (agent, main, canvas) = try await make([])
        let light = ScriptedBackend([.init(text: "Legions marched 30 km a day, building a fortified camp every night.")])
        agent.lightBackend = light
        let card = try await agent.session.createCard(in: "p-root", type: .topic, title: "Marching camps", summary: "A fort every night.", author: .agent)
        agent.writeBody(for: card.id)
        for _ in 0..<200 where agent.session.card(card.id)?.body == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(agent.session.card(card.id)?.body == "Legions marched 30 km a day, building a fortified camp every night.")
        #expect(main.prompts.isEmpty)
        #expect(light.prompts.first?.contains("\"Marching camps\": A fort every night.") == true)
        for _ in 0..<200 where canvas.ops.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(canvas.ops.last?.0 == "p-root")
        // Only once, and never over a body that's there.
        agent.writeBody(for: card.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(light.prompts.count == 1)
    }
}
