import Foundation

/// Enjin as a partner, not a vending machine: it watches what the explorer does
/// (AttentionLog) and, now and then, responds on its own: a line, a question,
/// or one card right where they're looking (AgentSession.nudge).
///
/// It stays out of the way: never while Enjin is working, typing is going on,
/// or a question is open; not soon after Enjin last spoke; only about something
/// they've really dwelt on, and never twice about the same thing. Each nudge the
/// explorer ignores doubles the wait before the next.
@MainActor
public final class Companion {
    public var enabled = true
    /// Quiet for this long after any turn ends.
    public static let quietAfterTurn: TimeInterval = 20
    /// Minimum time between nudges (doubles with each one ignored, up to 8×).
    public static let baseGap: TimeInterval = 45

    private let agent: AgentSession
    private let attention: AttentionLog
    private let clock: () -> Date
    private var lastNudge: Date?
    private var respondedSinceNudge = true
    private(set) var ignored = 0
    private var noticed: Set<String> = []

    public init(agent: AgentSession, attention: AttentionLog, clock: @escaping () -> Date = Date.init) {
        self.agent = agent
        self.attention = attention
        self.clock = clock
    }

    /// The explorer asked, answered or tapped a suggestion: they're engaged.
    public func explorerSpoke() {
        respondedSinceNudge = true
        ignored = 0
    }

    /// Look at what's happened and maybe chime in. Call when attention arrives.
    /// Returns the observation it acted on (for tests and logs).
    @discardableResult
    public func consider(portalId: String, typing: Bool = false) -> String? {
        guard enabled, !typing, !agent.isRunning, agent.question == nil else { return nil }
        let now = clock()
        if let end = agent.lastTurnEnded, now.timeIntervalSince(end) < Self.quietAfterTurn { return nil }
        let wait = Self.baseGap * pow(2, Double(min(ignored + (respondedSinceNudge ? 0 : 1), 3)))
        if let last = lastNudge, now.timeIntervalSince(last) < wait { return nil }
        let since = [agent.lastTurnEnded, lastNudge].compactMap { $0 }.max()
        guard let (event, ms) = attention.strongestInterest(since: since, in: portalId, excluding: noticed) else { return nil }
        noticed.insert(AttentionLog.key(event))
        if lastNudge != nil && !respondedSinceNudge { ignored += 1 }
        lastNudge = now
        respondedSinceNudge = false
        let observation = describe(event, ms: ms)
        agent.nudge(observation, portalId: portalId, focusCardId: event.cardId)
        return observation
    }

    private func describe(_ e: AttentionEvent, ms: Int) -> String {
        let seconds = max(1, ms / 1000)
        let what: String
        if let id = e.cardId, let card = agent.session.card(id) {
            what = "\"\(card.title)\" (\(id))"
        } else if let label = e.label {
            what = "the part \"\(label)\" of the model"
        } else {
            what = "this world"
        }
        return e.kind == .play
            ? "They've been playing with \(what) for about \(seconds) seconds."
            : "They've been looking at \(what) for about \(seconds) seconds."
    }
}
