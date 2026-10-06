import Foundation
import os

/// Local, append-only usage log for the two-week verdict (plan §9). Never leaves the device
/// unless someone exports a debug bundle by hand.
public actor Telemetry {
    public let url: URL
    private let log = Logger(subsystem: "cc.wckd.enjin", category: "telemetry")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public init(url: URL) {
        self.url = url
    }

    public func record(_ event: String, _ fields: [String: JSONValue] = [:], at date: Date = .now) {
        var obj = fields
        obj["event"] = .string(event)
        obj["t"] = .string(date.formatted(.iso8601))
        do {
            var line = try encoder.encode(JSONValue.object(obj))
            line.append(0x0A)
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: nil)
            }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
        } catch {
            log.error("telemetry write failed: \(error.localizedDescription)")
        }
    }

    /// All events, oldest first (for the stats screen and the spend cap).
    public func events() -> [JSONValue] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0)) }
    }

    /// USD spent on agent turns since local midnight.
    public func spentToday(now: Date = .now, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: now)
        return events().reduce(0) { sum, e in
            guard e["event"]?.stringValue == "agent_turn", case .number(let usd)? = e["cost"],
                  let t = e["t"]?.stringValue, let d = try? Date(t, strategy: .iso8601), d >= start else { return sum }
            return sum + usd
        }
    }
}
