import Foundation
import Testing
@testable import EnjinKit

/// A model that follows a script: each step is some tool calls and/or reply text.
final class ScriptedBackend: AgentBackend, @unchecked Sendable {
    struct Step {
        var events: [ProviderEvent] = []
        var calls: [(String, JSONValue)] = []
        var text = ""
    }

    let modelId = "claude-opus-5-5"
    let supportsWebSearch = true
    let isReduced: Bool
    private let lock = NSLock()
    private var steps: [Step]
    private(set) var prompts: [String] = []
    private(set) var threadLengths: [Int] = []
    var delay: Duration?

    init(_ steps: [Step], reduced: Bool = false) {
        self.steps = steps
        self.isReduced = reduced
    }

    func run(thread: inout [JSONValue], system: String, tools: [JSONValue],
             onEvent: @escaping @Sendable (ProviderEvent) -> Void,
             execute: @escaping @Sendable (String, JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult {
        lock.withLock {
            prompts.append(thread.last?["content"]?.stringValue ?? "")
            threadLengths.append(thread.count)
        }
        if let delay { try await Task.sleep(for: delay) }
        let step: Step? = lock.withLock { steps.isEmpty ? nil : steps.removeFirst() }
        guard let step else { return AgentTurnResult(stop: .done, rounds: 1, usage: .init(), firstEventMs: 1, totalMs: 1) }
        for e in step.events { onEvent(e) }
        await Task.yield()
        var results: [JSONValue] = []
        for (i, (name, input)) in step.calls.enumerated() {
            onEvent(.toolUse(id: "toolu_\(i)", name: name, input: input, raw: ""))
            switch await execute(name, input) {
            case .ok(let s): results.append(.object(["type": .string("tool_result"), "tool_use_id": .string("toolu_\(i)"), "content": .string(s)]))
            case .error(let s): results.append(.object(["type": .string("tool_result"), "tool_use_id": .string("toolu_\(i)"), "content": .string(s), "is_error": .bool(true)]))
            }
        }
        thread.append(.object(["role": .string("assistant"), "content": .string("(tools)")]))
        if !results.isEmpty { thread.append(.object(["role": .string("user"), "content": .array(results)])) }
        onEvent(.textDelta(step.text))
        thread.append(.object(["role": .string("assistant"), "content": .string(step.text)]))
        var usage = MessageAccumulator.Usage()
        usage.inputTokens = 1000
        usage.outputTokens = 200
        return AgentTurnResult(stop: .done, rounds: 2, usage: usage, firstEventMs: 300, totalMs: 1200)
    }

    var lastResults: [String] = []
}

@MainActor
final class FakeCanvas: CanvasSink {
    var ops: [(String, [CardOp])] = []
    var flashed: [String] = []
    var files: [BridgeFile] = []
    var headers: [NativeMethod.SetHeader] = []
    var busy: [(String, String?)] = []
    func apply(portalId: String, ops: [CardOp]) async { self.ops.append((portalId, ops)) }
    func flash(cardId: String) async { flashed.append(cardId) }
    func addFiles(_ files: [BridgeFile]) async { self.files += files }
    func setHeader(_ header: NativeMethod.SetHeader) async { headers.append(header) }
    func setBusy(portalId: String, message: String?) async { busy.append((portalId, message)) }
}

func card(_ title: String, stub: Bool = false, sources: [String]? = nil) -> JSONValue {
    var o: [String: JSONValue] = ["title": .string(title), "summary": .string("About \(title)."), "isStub": .bool(stub)]
    if let sources { o["sources"] = .array(sources.map { .string($0) }) }
    return .object(o)
}

func createCards(_ cards: [JSONValue], parent: String? = nil) -> (String, JSONValue) {
    var o: [String: JSONValue] = ["cards": .array(cards)]
    if let parent { o["parentCardId"] = .string(parent) }
    return ("createCards", .object(o))
}

@MainActor
struct AgentSessionTests {
    func make(_ steps: [ScriptedBackend.Step], telemetry: Telemetry? = nil) async throws -> (AgentSession, ScriptedBackend, FakeCanvas) {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        _ = try await session.scene(for: "p-root")
        let backend = ScriptedBackend(steps)
        let agent = AgentSession(session: session, backend: backend, telemetry: telemetry ?? Telemetry(url: tempRoot().appendingPathComponent("t.jsonl")))
        let canvas = FakeCanvas()
        agent.canvas = canvas
        return (agent, backend, canvas)
    }

    func waitIdle(_ agent: AgentSession) async {
        for _ in 0..<1000 where agent.isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func askCreatesCardsAndSuggests() async throws {
        let (agent, backend, canvas) = try await make([
            .init(calls: [createCards([card("Testudo"), card("Who paid them?", stub: true)]), ("suggestFocus", .object(["cardId": .string("c-roads"), "reason": .string("roads won wars")]))],
                  text: "Here's how the testudo worked."),
        ])
        agent.ask("how did they fight?", portalId: "p-root", focusCardId: "c-legions")
        await waitIdle(agent)

        let made = agent.session.activeCards(in: "p-root").filter { $0.createdBy == .agent && $0.createdByTurnId != nil }
        #expect(made.map(\.title) == ["Testudo", "Who paid them?"])
        #expect(made.map(\.state) == [.filled, .stub])
        #expect(canvas.ops.first?.0 == "p-root")
        #expect(agent.reply == "Here's how the testudo worked.")
        #expect(agent.suggestion == .init(cardId: "c-roads", reason: "roads won wars"))
        #expect(canvas.flashed == ["c-roads"])
        #expect(agent.status == .idle)
        #expect(agent.canUndo)
        #expect(backend.prompts.first?.contains("The kid says: how did they fight?") == true)
        #expect(backend.prompts.first?.contains("Closest to the center of their screen: c-legions") == true)
    }

    @Test func capsCardsPerCallAndPerTurn() async throws {
        let five = (1...5).map { card("A\($0)") }
        let (agent, _, _) = try await make([.init(calls: [createCards(five), createCards(five)], text: "")])
        agent.ask("everything!", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(agent.session.activeCards(in: "p-root").filter { $0.createdByTurnId != nil }.count == AgentTools.maxCardsPerTurn)
    }

    @Test func neverChangesKidCardsAndUndoRevertsAgentChanges() async throws {
        let (agent, _, canvas) = try await make([])
        let kid = try await agent.session.createCard(in: "p-root", type: .note, title: "Mine", summary: "my idea", author: .kid)
        let backend = ScriptedBackend([
            .init(calls: [
                ("updateCard", .object(["cardId": .string(kid.id), "title": .string("Hijacked")])),
                ("updateCard", .object(["cardId": .string("c-roads"), "summary": .string("Rewritten")])),
                createCards([card("New one")]),
            ]),
        ])
        agent.backend = backend
        agent.ask("tidy up", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(agent.session.card(kid.id)?.title == "Mine")
        #expect(agent.session.card("c-roads")?.summary == "Rewritten")
        let newId = try #require(agent.session.activeCards(in: "p-root").first { $0.title == "New one" }?.id)

        await agent.undoLastTurn()
        #expect(agent.session.card("c-roads")?.summary == "80,000 km of paved roads that moved armies, mail and trade.")
        #expect(agent.session.card(newId)?.isActive == false)
        #expect(canvas.ops.contains { $0.1.contains(.delete(cardId: newId)) })
        #expect(!agent.canUndo)
    }

    @Test func fillingAStubPutsCardsInsideItAndMarksItFilled() async throws {
        let (agent, _, canvas) = try await make([
            .init(calls: [
                ("updateCard", .object(["cardId": .string("c-emperors"), "summary": .string("Rome had 70+ emperors."), "state": .string("filled")])),
                createCards([card("Augustus"), card("The bad ones", stub: true)], parent: "c-emperors"),
            ], text: "Let's meet the emperors."),
        ])
        let portal = try #require(try await agent.session.ensurePortal(for: "c-emperors"))
        agent.fill(cardId: "c-emperors")
        await waitIdle(agent)
        #expect(agent.session.card("c-emperors")?.state == .filled)
        #expect(agent.session.activeCards(in: portal.portalId).map(\.title) == ["Augustus", "The bad ones"])
        #expect(canvas.ops.contains { $0.0 == portal.portalId })
        // The stub went filling -> filled on the parent canvas.
        let states = canvas.ops.filter { $0.0 == "p-root" }.flatMap(\.1).compactMap { op -> CardState? in
            if case .upsert(let c) = op, c.id == "c-emperors" { c.state } else { nil }
        }
        #expect(states.first == .filling)
        #expect(states.last == .filled)
        #expect(states.contains(.filled))
    }

    @Test func cancellingAFillPutsTheStubBack() async throws {
        let (agent, backend, _) = try await make([.init(text: "never")])
        backend.delay = .seconds(5)
        _ = try await agent.session.ensurePortal(for: "c-fall")
        agent.fill(cardId: "c-fall")
        try await Task.sleep(for: .milliseconds(50))
        #expect(agent.session.card("c-fall")?.state == .filling)
        agent.cancel()
        await waitIdle(agent)
        #expect(agent.session.card("c-fall")?.state == .stub)
        #expect(agent.status == .idle)
    }

    @Test func spendCapStopsTurns() async throws {
        let telemetry = Telemetry(url: tempRoot().appendingPathComponent("t.jsonl"))
        await telemetry.record("agent_turn", ["cost": .number(5)])
        let (agent, backend, _) = try await make([.init(text: "hi")], telemetry: telemetry)
        agent.dailyCapUSD = 2
        agent.ask("hello", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(agent.status == .failed("Enjin is resting for today. Come back tomorrow!"))
        #expect(backend.prompts.isEmpty)
    }

    @Test func cardsOnlyCiteURLsTheModelActuallySaw() async throws {
        let seen = ProviderEvent.WebResult(title: "Roman roads", url: "https://example.org/roads")
        let (agent, _, _) = try await make([
            .init(events: [.serverToolUse(name: "web_search", input: .object(["query": .string("roman roads")])), .webSearchResults([seen])],
                  calls: [createCards([card("Via Appia", sources: ["https://example.org/roads", "https://made-up.example/fake"])])]),
        ])
        agent.ask("roads?", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        let c = try #require(agent.session.activeCards(in: "p-root").first { $0.title == "Via Appia" })
        #expect(c.sources == [Source(title: "Roman roads", url: "https://example.org/roads")])
    }

    @Test func recordsTurnTelemetryWithCost() async throws {
        let url = tempRoot().appendingPathComponent("t.jsonl")
        let telemetry = Telemetry(url: url)
        let (agent, _, _) = try await make([.init(text: "ok")], telemetry: telemetry)
        agent.ask("hi", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        let turn = try #require(await telemetry.events().first { $0["event"]?.stringValue == "agent_turn" })
        // 1000 in * $4/M + 200 out * $20/M = $0.008
        #expect(turn["cost"] == .number(0.008))
        #expect(await telemetry.spentToday() == 0.008)
    }

    @Test func startsAFreshThreadInsteadOfEditingHistory() async throws {
        let steps = (0..<(AgentSession.maxThreadTurns + 1)).map { _ in ScriptedBackend.Step(text: "ok") }
        let (agent, backend, _) = try await make(steps)
        for i in 0...AgentSession.maxThreadTurns {
            agent.ask("q\(i)", portalId: "p-root", focusCardId: nil)
            await waitIdle(agent)
        }
        // Each turn adds user + assistant(tools) + assistant(text); the 9th starts over at 1.
        #expect(backend.threadLengths.first == 1)
        #expect(backend.threadLengths[1] == 4)
        #expect(backend.threadLengths.last == 1)
    }

    @Test func kidChangesReachTheNextPrompt() async throws {
        let (agent, backend, _) = try await make([.init(text: "ok")])
        _ = try await agent.session.createCard(in: "p-root", type: .note, title: "Pizza?", summary: "did they have pizza", author: .kid)
        agent.ask("well?", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(backend.prompts.first?.contains("- made a card \"Pizza?\"") == true)
        #expect(agent.session.changeLog.isEmpty, "the log is drained into the prompt")
    }

    @Test func noKeyIsAFriendlyError() async throws {
        let (agent, _, _) = try await make([])
        agent.backend = nil
        agent.ask("hi", portalId: "p-root", focusCardId: nil)
        await waitIdle(agent)
        #expect(agent.status == .failed("Enjin needs a key to think. Ask a parent to add one in Settings."))
    }
}

@MainActor
struct UndoWithCanvasTests {
    @Test func undoSurvivesTheCanvasSavingAroundIt() async throws {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        _ = try await session.scene(for: "p-root")
        let agent = AgentSession(session: session, backend: ScriptedBackend([.init(calls: [createCards([card("One"), card("Two")])])]), telemetry: nil)
        let canvas = FakeCanvas()
        agent.canvas = canvas
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        for _ in 0..<500 where agent.isRunning { try await Task.sleep(for: .milliseconds(5)) }

        let base = ["c-legions", "c-roads", "c-emperors", "c-fall"]
        let made = session.activeCards(in: "p-root").filter { $0.createdBy == .agent && $0.createdByTurnId != nil }.map(\.id)
        #expect(made.count == 2)
        // The canvas saves with the new cards on it...
        try await session.saveElements(portalId: "p-root", elements: (base + made).map(SessionTests.frame))
        await agent.undoLastTurn()
        #expect(session.activeCards(in: "p-root").count == 4)
        // ...and a save that was already in flight (debounced) lands after the undo.
        try await session.saveElements(portalId: "p-root", elements: (base + made).map(SessionTests.frame))
        #expect(session.activeCards(in: "p-root").count == 4, "a stale canvas save must not bring undone cards back")
        try await session.saveElements(portalId: "p-root", elements: base.map(SessionTests.frame))
        #expect(session.activeCards(in: "p-root").count == 4)
    }
}

@MainActor
struct PrefetchTests {
    @Test func prefetchFillsQuietlyAndDoesNotStealUndo() async throws {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        let backend = ScriptedBackend([
            .init(calls: [createCards([card("Seen by kid")])], text: "visible reply"),
            .init(calls: [("updateCard", .object(["cardId": .string("c-fall"), "summary": .string("Filled early."), "state": .string("filled")])),
                          createCards([card("Inside fall")], parent: "c-fall")], text: "background"),
        ])
        let agent = AgentSession(session: session, backend: backend, telemetry: nil)
        agent.prefetchEnabled = true
        let canvas = FakeCanvas()
        agent.canvas = canvas
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        for _ in 0..<500 where agent.isRunning { try await Task.sleep(for: .milliseconds(5)) }

        agent.prefetch(cardId: "c-fall")
        try await Task.sleep(for: .milliseconds(20))
        for _ in 0..<500 where agent.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.card("c-fall")?.state == .filled)
        #expect(agent.reply == "visible reply", "prefetch doesn't touch the dock")

        await agent.undoLastTurn()
        #expect(session.activeCards(in: "p-root").contains { $0.title == "Seen by kid" } == false, "undo targets the kid's turn")
        #expect(session.card("c-fall")?.state == .filled, "the prefetch fill stays")
    }
}
