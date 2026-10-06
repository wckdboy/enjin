import Foundation

/// Server-sent events from the Messages API. Every Anthropic event carries its
/// type inside the `data:` JSON, so we only need the data lines.
public enum SSE {
    public static func event(fromLine line: some StringProtocol) throws -> JSONValue? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).drop { $0 == " " }
        guard !payload.isEmpty else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
    }
}
