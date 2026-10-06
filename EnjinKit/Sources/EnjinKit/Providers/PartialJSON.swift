import Foundation

/// Parses a JSON document that's still streaming in (a tool's input_json_delta
/// so far), by closing whatever is open: strings, arrays, objects. Incomplete
/// tokens at the end (half a literal, a key with no value yet) are dropped.
/// Only used for live previews; the final input is parsed strictly.
public enum PartialJSON {
    nonisolated(unsafe) static let jsonNumber = #/-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/#

    public static func parse(_ text: String) -> JSONValue? {
        guard let completed = complete(text) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(completed.utf8))
    }

    enum Container { case object, array }
    /// Where we are inside the innermost object.
    enum ObjectState { case expectKey, inKey, expectColon, expectValue, inValue, afterValue }

    static func complete(_ text: String) -> String? {
        var out = ""
        var stack: [Container] = []
        var objectStates: [ObjectState] = []
        var inString = false
        var escape = false
        // Index in `out` where the current partial token (string or literal) started,
        // so it can be cut if it can't be completed.
        var tokenStart: String.Index?
        // Last point where the document could be closed validly.
        var safe: (end: String.Index, stack: [Container], states: [ObjectState])?

        func markSafe() { safe = (out.endIndex, stack, objectStates) }
        func valueDone() {
            if stack.last == .object, !objectStates.isEmpty { objectStates[objectStates.count - 1] = .afterValue }
            markSafe()
        }

        markSafe()
        for ch in text {
            if inString {
                out.append(ch)
                if escape { escape = false; continue }
                if ch == "\\" { escape = true; continue }
                if ch == "\"" {
                    inString = false
                    tokenStart = nil
                    if stack.last == .object, objectStates.last == .inKey {
                        objectStates[objectStates.count - 1] = .expectColon
                    } else {
                        valueDone()
                    }
                }
                continue
            }
            switch ch {
            case "{":
                out.append(ch); stack.append(.object); objectStates.append(.expectKey); markSafe()
            case "[":
                out.append(ch); stack.append(.array); markSafe()
            case "}", "]":
                out.append(ch)
                if stack.popLast() == .object { objectStates.removeLast() }
                valueDone()
            case "\"":
                tokenStart = out.endIndex
                out.append(ch)
                inString = true
                if stack.last == .object, objectStates.last == .expectKey { objectStates[objectStates.count - 1] = .inKey }
            case ":":
                out.append(ch)
                if stack.last == .object { objectStates[objectStates.count - 1] = .expectValue }
            case ",":
                out.append(ch)
                if stack.last == .object { objectStates[objectStates.count - 1] = .expectKey }
            case " ", "\n", "\t", "\r":
                out.append(ch)
            default:
                // Literal or number character.
                if tokenStart == nil { tokenStart = out.endIndex }
                out.append(ch)
                // A literal/number counts as done once it parses on its own.
                let token = String(out[tokenStart!...])
                if ["true", "false", "null"].contains(token) || token.wholeMatch(of: jsonNumber) != nil {
                    valueDone()
                    if ["true", "false", "null"].contains(token) { tokenStart = nil }
                }
            }
        }

        // Close an open string value (keep the partial text: that's the streaming content).
        if inString {
            if escape { out.removeLast() }
            // Drop a half-written \uXXXX escape.
            if let r = out.range(of: #"\\u[0-9a-fA-F]{0,3}$"#, options: .regularExpression) { out.removeSubrange(r) }
            if stack.last == .object, objectStates.last == .inKey {
                // A key without a value yet: cut back to the last safe point.
                guard let s = safe else { return nil }
                return close(String(out[..<s.end]), s.stack)
            }
            out.append("\"")
            return close(out, stack)
        }
        guard let s = safe else { return nil }
        return close(String(out[..<s.end]), s.stack)
    }

    private static func close(_ prefix: String, _ stack: [Container]) -> String {
        var s = prefix
        // A trailing comma (or colon) before the closers would be invalid.
        while let last = s.last, last == "," || last == ":" || last.isWhitespace { s.removeLast() }
        for c in stack.reversed() { s.append(c == .object ? "}" : "]") }
        return s
    }
}
