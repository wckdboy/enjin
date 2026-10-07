import Foundation

/// One thing the explorer did in the world (from the `attention` bridge message).
public struct AttentionEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case look, tap, explode, turn, play, zoomInto, dive, rise }
    public var kind: Kind
    public var cardId: String?
    /// A model part, or a title when there's no card.
    public var label: String?
    /// How long (look, play).
    public var ms: Int?
    public init(kind: Kind, cardId: String? = nil, label: String? = nil, ms: Int? = nil) {
        self.kind = kind; self.cardId = cardId; self.label = label; self.ms = ms
    }
}

/// What the explorer has been doing lately: the raw material for Enjin noticing
/// things ("you've been playing with that slider for a while") and for the
/// companion deciding when to chime in. Recent events only; it forgets.
@MainActor
public final class AttentionLog {
    public struct Entry: Equatable, Sendable {
        public var event: AttentionEvent
        public var portalId: String
        public var at: Date
    }

    public static let capacity = 60
    public private(set) var entries: [Entry] = []
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    public func record(_ events: [AttentionEvent], in portalId: String) {
        let now = clock()
        entries += events.map { Entry(event: $0, portalId: portalId, at: now) }
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// When they last did anything at all.
    public var lastActivity: Date? { entries.last?.at }

    public func since(_ date: Date?) -> [Entry] {
        guard let date else { return entries }
        return entries.filter { $0.at > date }
    }

    /// The thing they've dwelt on longest since `date` (a card or a part), with how long, if it's worth noticing.
    public func strongestInterest(since date: Date?, in portalId: String, minMs: Int = 7000, excluding: Set<String> = []) -> (event: AttentionEvent, ms: Int)? {
        var totals: [String: (AttentionEvent, Int)] = [:]
        for e in since(date) where e.portalId == portalId && (e.event.kind == .look || e.event.kind == .play) {
            let key = Self.key(e.event)
            if excluding.contains(key) { continue }
            let ms = (totals[key]?.1 ?? 0) + (e.event.ms ?? 0)
            totals[key] = (e.event, ms)
        }
        guard let best = totals.values.max(by: { $0.1 < $1.1 }), best.1 >= minMs else { return nil }
        return (best.0, best.1)
    }

    /// What an event is about: a card, or a part of a model.
    public static func key(_ e: AttentionEvent) -> String {
        e.cardId ?? "part:\(e.label ?? "")"
    }

    /// A few plain lines for the prompt: what they did, most recent last, merged and named.
    public func summary(since date: Date? = nil, names: (String) -> String?) -> String? {
        let recent = since(date).suffix(24)
        guard !recent.isEmpty else { return nil }
        var lines: [String] = []
        var looked: [String: Int] = [:]
        var order: [String] = []
        func name(_ e: AttentionEvent) -> String {
            if let id = e.cardId, let n = names(id) { return "\"\(n)\"" }
            if let l = e.label { return "the part \"\(l)\"" }
            return "the world"
        }
        for entry in recent {
            let e = entry.event
            let n = name(e)
            switch e.kind {
            case .look:
                if looked[n] == nil { order.append(n) }
                looked[n, default: 0] += e.ms ?? 0
            case .play: lines.append("played with \(n)\(e.ms.map { " for \(max(1, $0 / 1000))s" } ?? "")")
            case .tap: lines.append("tapped \(n)")
            case .explode: lines.append("pulled the model apart")
            case .turn: lines.append("turned the model around")
            case .zoomInto: lines.append("zoomed right into \(n)")
            case .dive: lines.append("went inside \(n)")
            case .rise: lines.append("came back out to \(n)")
            }
        }
        let looks = order.compactMap { n in looked[n].flatMap { $0 >= 2500 ? "looked at \(n) for \($0 / 1000)s" : nil } }
        let all = looks + lines.reduce(into: [String]()) { out, l in if out.last != l { out.append(l) } }
        guard !all.isEmpty else { return nil }
        return all.suffix(10).map { "- \($0)" }.joined(separator: "\n")
    }
}
