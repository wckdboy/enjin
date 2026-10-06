import Foundation
import Observation
import os

/// Where agent output lands on screen. CanvasController implements it; tests fake it.
@MainActor
public protocol CanvasSink: AnyObject {
    func apply(portalId: String, ops: [CardOp]) async
    func flash(cardId: String) async
}

/// Runs agent turns against one open notebook (plan §5). One turn at a time:
/// a new kid request cancels the one in flight.
@MainActor
@Observable
public final class AgentSession {
    public enum Activity: Equatable, Sendable {
        case thinking
        case searching(String)
        case writing
    }

    public enum Status: Equatable, Sendable {
        case idle
        case working(Activity)
        case failed(String)
    }

    public enum Kind: String, Sendable { case ask, fill, prefetch }

    public struct Suggestion: Equatable, Sendable {
        public var cardId: String
        public var reason: String
    }

    public private(set) var status: Status = .idle
    /// The agent's short chat reply for the current/last turn.
    public private(set) var reply = ""
    public private(set) var suggestion: Suggestion?
    public var canUndo: Bool { lastTurn != nil && !(lastTurn?.isEmpty ?? true) }
    /// True while a turn (including a background prefetch) is in flight.
    /// Stored (not derived from `task`) so SwiftUI observes it.
    public private(set) var isRunning = false
    /// Card currently being filled by a prefetch, if any.
    public private(set) var prefetchingCardId: String?

    @ObservationIgnored public var backend: AgentBackend?
    @ObservationIgnored public var dailyCapUSD: Double = 2
    @ObservationIgnored public let session: NotebookSession
    @ObservationIgnored public weak var canvas: CanvasSink?
    @ObservationIgnored private let telemetry: Telemetry?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var threads: [String: [JSONValue]] = [:]
    @ObservationIgnored private var tail: [PromptComposer.TailEntry] = []
    private var lastTurn: TurnRecord?
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "agent")

    /// Start a fresh thread after this many kid turns, rather than editing history
    /// (edited history invalidates thinking blocks; the canvas summary carries context).
    public static let maxThreadTurns = 8

    /// What a turn changed, for undo.
    struct TurnRecord {
        var id: String
        var created: [String] = []
        var previous: [String: StoredCard] = [:]
        var isEmpty: Bool { created.isEmpty && previous.isEmpty }
    }

    public init(session: NotebookSession, backend: AgentBackend?, telemetry: Telemetry?) {
        self.session = session
        self.backend = backend
        self.telemetry = telemetry
    }

    // MARK: - Requests

    public func ask(_ text: String, portalId: String, focusCardId: String?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        start(.ask, request: .ask(text), portalId: portalId, focusCardId: focusCardId, kidSaid: text)
    }

    /// The kid dived into a stub: fill it, with cards appearing in its portal.
    public func fill(cardId: String) {
        guard let card = session.card(cardId), card.state == .stub || card.state == .error else { return }
        // Already being prefetched: let that finish; the kid will see cards arrive.
        if prefetchingCardId == cardId, task != nil { return }
        guard let portal = session.childPortal(of: cardId) else { return }
        start(.fill, request: .fill(cardId: cardId), portalId: portal.portalId, focusCardId: nil, kidSaid: "(dived into \(card.title))")
    }

    /// Background fill of a stub the kid is lingering on. Never interrupts real work.
    public func prefetch(cardId: String) {
        guard task == nil, backend?.isReduced == false, let card = session.card(cardId), card.state == .stub, card.type == .topic else { return }
        Task {
            guard let portal = try? await session.ensurePortal(for: cardId) else { return }
            guard task == nil else { return }
            prefetchingCardId = cardId
            start(.prefetch, request: .fill(cardId: cardId), portalId: portal.portalId, focusCardId: nil, kidSaid: "(looked at \(card.title))")
        }
    }

    public func cancel() {
        task?.cancel()
    }

    public func dismissError() {
        if case .failed = status { status = .idle }
    }

    public func clearSuggestion() {
        suggestion = nil
    }

    // MARK: - Undo

    public func undoLastTurn() async {
        guard let turn = lastTurn else { return }
        lastTurn = nil
        var ops: [String: [CardOp]] = [:]
        for id in turn.created {
            guard let c = session.card(id) else { continue }
            try? await session.deleteCard(id)
            ops[c.portalId, default: []].append(.delete(cardId: id))
        }
        for (id, old) in turn.previous {
            try? await session.restore(old)
            if let c = session.card(id) { ops[c.portalId, default: []].append(.upsert(session.bridgeCard(c))) }
        }
        // Parents whose child counts changed.
        for parent in Set(turn.created.compactMap { session.card($0).flatMap { session.ownerCardId(of: $0.portalId) } }) {
            if let p = session.card(parent) { ops[p.portalId, default: []].append(.upsert(session.bridgeCard(p))) }
        }
        for (portalId, list) in ops { await canvas?.apply(portalId: portalId, ops: list) }
        await telemetry?.record("undo_agent_turn", ["turn": .string(turn.id)])
        reply = ""
        suggestion = nil
    }

    // MARK: - Turn

    private func start(_ kind: Kind, request: PromptComposer.Request, portalId: String, focusCardId: String?, kidSaid: String) {
        if kind != .prefetch { task?.cancel() }
        let previous = task
        isRunning = true
        let next = Task { [weak self] in
            await previous?.value // let a cancelled turn finish its cleanup first
            await self?.runTurn(kind, request: request, portalId: portalId, focusCardId: focusCardId, kidSaid: kidSaid)
        }
        task = next
        Task { [weak self] in
            await next.value
            // Only the latest turn clears the flag.
            if let self, self.task == next || self.task == nil {
                self.task = nil
                self.isRunning = false
            }
        }
    }

    private func runTurn(_ kind: Kind, request: PromptComposer.Request, portalId: String, focusCardId: String?, kidSaid: String) async {
        defer {
            if kind == .prefetch { prefetchingCardId = nil }
        }
        guard let backend else {
            if kind != .prefetch { status = .failed("Enjin needs a key to think. Ask a parent to add one in Settings.") }
            return
        }
        let spent = await telemetry?.spentToday() ?? 0
        if spent >= dailyCapUSD {
            if kind != .prefetch { status = .failed("Enjin is resting for today. Come back tomorrow!") }
            return
        }

        let turnId = "t-\(UUID().uuidString.prefix(8).lowercased())"
        var record = TurnRecord(id: turnId)
        var fillingId: String?
        if case .fill(let cardId) = request, let card = session.card(cardId) {
            fillingId = cardId
            record.previous[cardId] = card
            await setState(cardId, .filling)
        }
        if kind != .prefetch {
            status = .working(.thinking)
            reply = ""
            suggestion = nil
        }

        let changes = session.drainChangeLog()
        let userText = PromptComposer.compose(session: session, portalId: portalId, focusCardId: focusCardId, request: request,
                                              changes: changes, tail: tail.filter { $0.portalTitle != session.portal(portalId)?.title },
                                              compact: backend.isReduced)
        var thread = threads[portalId] ?? []
        if thread.filter({ $0["role"] == .string("user") && $0["content"]?.stringValue != nil }).count >= Self.maxThreadTurns { thread = [] }
        thread.append(.object(["role": .string("user"), "content": .string(userText)]))

        let tools = backend.isReduced ? AgentTools.reduced : AgentTools.all
        let executor = ToolExecutor(agent: self, portalId: portalId, turnId: turnId)
        let foreground = kind != .prefetch
        let started = Date()
        var made: [String] = []

        do {
            let result = try await backend.run(thread: &thread, system: Persona.system, tools: tools, onEvent: { [weak self, executor] e in
                Task { @MainActor in
                    executor.observe(e)
                    guard foreground, let self else { return }
                    switch e {
                    case .textDelta(let t): self.reply += t
                    case .serverToolUse(_, let input): self.status = .working(.searching(input["query"]?.stringValue ?? ""))
                    case .toolUse: self.status = .working(.writing)
                    default: break
                    }
                }
            }, execute: { [executor] name, input in
                await executor.execute(name, input)
            })
            try Task.checkCancellation()

            threads[portalId] = thread
            record.created = executor.created
            record.previous.merge(executor.previous) { first, _ in first }
            made = executor.created.compactMap { session.card($0)?.title }
            if let id = fillingId, session.card(id)?.state == .filling { await setState(id, .filled) }
            // Undo is for what the kid saw happen; a background prefetch never replaces it.
            if !record.isEmpty && kind != .prefetch { lastTurn = record }
            tail.append(.init(portalTitle: session.portal(portalId)?.title ?? "", kidSaid: kidSaid, cardsMade: made))
            if tail.count > 3 { tail.removeFirst(tail.count - 3) }
            if foreground {
                switch result.stop {
                case .refused: status = .failed("Enjin can't help with that one. Try asking a different way.")
                default: status = .idle
                }
            }
            await Task.yield() // let queued stream events land before counting searches
            let searches = executor.searches
            let cost = Pricing.of(backend.modelId).cost(result.usage, webSearches: searches)
            await telemetry?.record("agent_turn", [
                "kind": .string(kind.rawValue), "model": .string(backend.modelId), "turn": .string(turnId),
                "first_event_ms": result.firstEventMs.map { .number($0.rounded()) } ?? .null, "total_ms": .number(result.totalMs.rounded()),
                "rounds": .number(Double(result.rounds)), "stop": .string("\(result.stop)"), "cards": .number(Double(made.count)),
                "searches": .number(Double(searches)), "input_tokens": .number(Double(result.usage.inputTokens)),
                "output_tokens": .number(Double(result.usage.outputTokens)), "cache_read_tokens": .number(Double(result.usage.cacheReadInputTokens)),
                "cost": .number((cost * 10_000).rounded() / 10_000),
            ])
        } catch {
            // Cards already placed stay; a stub we were filling goes back to being a stub.
            if let id = fillingId, session.card(id)?.state == .filling { await setState(id, .stub) }
            if executor.created.count > 0 && kind != .prefetch {
                record.created = executor.created
                lastTurn = record
            }
            let cancelled = error is CancellationError || Task.isCancelled
            if foreground && !cancelled { status = .failed(Self.kidMessage(for: error)) }
            if cancelled && foreground { status = .idle }
            log.error("turn \(turnId) failed: \(error.localizedDescription)")
            await telemetry?.record("agent_turn", [
                "kind": .string(kind.rawValue), "model": .string(backend.modelId), "turn": .string(turnId),
                "total_ms": .number(Date().timeIntervalSince(started) * 1000), "error": .string(cancelled ? "cancelled" : "\(error)"),
            ])
        }
    }

    static func kidMessage(for error: Error) -> String {
        if let e = error as? AnthropicError {
            switch e {
            case .missingKey: return "Enjin needs a key to think. Ask a parent to add one in Settings."
            case .http(let status, _, _) where status == 401 || status == 403:
                return "Enjin's key isn't working. Ask a parent to check it in Settings."
            case .http(let status, _, _) where status == 429 || status == 529 || status >= 500:
                return "Enjin is busy right now. Try again in a moment."
            case .stream: return "Enjin got interrupted. Try again."
            default: return "Something went wrong. Try again."
            }
        }
        if let e = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(e.code) {
            return "Can't reach the internet. Try again when you're online."
        }
        return "Something went wrong. Try again."
    }

    fileprivate func setState(_ cardId: String, _ state: CardState) async {
        guard let c = try? await session.updateCard(cardId, by: .agent, { $0.state = state }) else { return }
        await canvas?.apply(portalId: c.portalId, ops: [.upsert(session.bridgeCard(c))])
    }

    fileprivate func setSuggestion(_ s: Suggestion) async {
        suggestion = s
        await canvas?.flash(cardId: s.cardId)
    }
}

/// Executes one turn's tool calls. Main-actor bound: it mutates the notebook.
@MainActor
final class ToolExecutor {
    private weak var agent: AgentSession?
    private let portalId: String
    private let turnId: String
    private(set) var created: [String] = []
    private(set) var previous: [String: StoredCard] = [:]
    /// URLs the model actually saw this turn; cards may only cite these.
    private var seen: [String: String] = [:]
    private(set) var searches = 0

    init(agent: AgentSession, portalId: String, turnId: String) {
        self.agent = agent
        self.portalId = portalId
        self.turnId = turnId
    }

    func observe(_ e: ProviderEvent) {
        switch e {
        case .webSearchResults(let rs): for r in rs { seen[r.url] = r.title }
        case .citation(let r, _): seen[r.url] = r.title
        case .serverToolUse: searches += 1
        default: break
        }
    }

    private func sources(_ urls: [String]?) -> [Source]? {
        let list = (urls ?? []).compactMap { url in seen[url].map { Source(title: $0, url: url) } }
        return list.isEmpty ? nil : Array(Set(list)).sorted { $0.url < $1.url }
    }

    func execute(_ name: String, _ input: JSONValue) async -> ToolOutcome {
        guard let agent else { return .error("session closed") }
        let session = agent.session
        do {
            switch name {
            case "createCards":
                let args = try input.decode(as: AgentTools.CreateCards.self)
                var target = portalId
                var parent: StoredCard?
                if let parentId = args.parentCardId {
                    guard let p = try await session.ensurePortal(for: parentId) else {
                        return .error("\(parentId) is not a topic card on this canvas, so cards can't go inside it.")
                    }
                    target = p.portalId
                    parent = session.card(parentId)
                }
                let room = AgentTools.maxCardsPerTurn - created.count
                guard room > 0 else { return .error("This turn already added \(AgentTools.maxCardsPerTurn) cards, the limit. Stop adding cards.") }
                let wanted = Array(args.cards.prefix(min(AgentTools.maxCardsPerCall, room)))
                var ids: [String] = []
                var ops: [CardOp] = []
                for c in wanted {
                    let card = try await session.createCard(
                        in: target, type: c.type ?? .topic, title: AgentTools.clip(c.title, AgentTools.titleLimit),
                        summary: AgentTools.clip(c.summary, AgentTools.summaryLimit),
                        body: c.body.map { AgentTools.clip($0, AgentTools.bodyLimit) }.flatMap { $0.isEmpty ? nil : $0 },
                        state: c.isStub ? .stub : .filled, author: .agent, turnId: turnId, sources: sources(c.sources))
                    ids.append(card.id)
                    ops.append(.upsert(session.bridgeCard(card)))
                }
                created += ids
                await agent.canvas?.apply(portalId: target, ops: ops)
                if let parent, let fresh = session.card(parent.id) {
                    await agent.canvas?.apply(portalId: fresh.portalId, ops: [.upsert(session.bridgeCard(fresh))]) // child count badge
                }
                var note = "Added \(ids.count) card(s): \(ids.joined(separator: ", "))."
                if wanted.count < args.cards.count { note += " \(args.cards.count - wanted.count) more were dropped (limit is \(AgentTools.maxCardsPerCall) per call, \(AgentTools.maxCardsPerTurn) per turn)." }
                return .ok(note)

            case "updateCard":
                let args = try input.decode(as: AgentTools.UpdateCard.self)
                guard let card = session.card(args.cardId), card.isActive else { return .error("No card \(args.cardId) on the canvas.") }
                guard card.createdBy == .agent else { return .error("\(args.cardId) is the kid's own card. Don't change it; make a new card instead.") }
                if previous[card.id] == nil && !created.contains(card.id) { previous[card.id] = card }
                let srcs = sources(args.sources)
                guard let updated = try await session.updateCard(card.id, by: .agent, {
                    if let t = args.title { $0.title = AgentTools.clip(t, AgentTools.titleLimit) }
                    if let s = args.summary { $0.summary = AgentTools.clip(s, AgentTools.summaryLimit) }
                    if let b = args.body { $0.body = AgentTools.clip(b, AgentTools.bodyLimit) }
                    if let st = args.state { $0.state = st } else if $0.state == .filling { $0.state = .filled }
                    if let srcs { $0.sources = srcs }
                }) else { return .error("No card \(args.cardId).") }
                await agent.canvas?.apply(portalId: updated.portalId, ops: [.upsert(session.bridgeCard(updated))])
                return .ok("Updated \(updated.id).")

            case "suggestFocus":
                let args = try input.decode(as: AgentTools.SuggestFocus.self)
                guard session.card(args.cardId)?.isActive == true else { return .error("No card \(args.cardId).") }
                await agent.setSuggestion(.init(cardId: args.cardId, reason: AgentTools.clip(args.reason, 80)))
                return .ok("Highlighted \(args.cardId) for the kid.")

            default:
                return .error("Unknown tool \(name).")
            }
        } catch let e as DecodingError {
            return .error("Invalid input for \(name): \(e)")
        } catch {
            return .error("\(name) failed: \(error.localizedDescription)")
        }
    }
}
