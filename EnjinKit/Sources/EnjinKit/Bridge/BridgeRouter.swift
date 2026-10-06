import Foundation

public enum BridgeErrorCode: Int, Sendable {
    case versionMismatch = -32000
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}

public struct BridgeError: Error, Equatable, Sendable {
    public var code: Int
    public var message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
}

/// Dispatches web->native requests to typed handlers and builds JSON-RPC
/// responses. Transport-free so it can be tested without a WKWebView.
@MainActor
public final class BridgeRouter {
    public typealias RawHandler = @MainActor (JSONValue) async throws -> JSONValue

    private var handlers: [String: RawHandler] = [:]

    public init() {}

    public func on<P: Decodable, R: Encodable>(_ method: String, _ params: P.Type, handler: @escaping @MainActor (P) async throws -> R) {
        handlers[method] = { raw in
            let p: P
            do { p = try raw.decode(as: P.self) } catch {
                throw BridgeError(code: BridgeErrorCode.invalidParams.rawValue, message: "\(method): \(error)")
            }
            return try JSONValue.from(try await handler(p))
        }
    }

    /// Handles one request. Never throws: every failure becomes an error response.
    public func handle(_ request: JSONValue) async -> JSONValue {
        let id = request["id"]?.stringValue ?? "?"
        func fail(_ code: BridgeErrorCode, _ message: String) -> JSONValue {
            .object(["v": .number(Double(bridgeProtocolVersion)), "id": .string(id),
                     "error": .object(["code": .number(Double(code.rawValue)), "message": .string(message)])])
        }
        guard case .number(let v)? = request["v"], case .string(let method)? = request["method"] else {
            return fail(.invalidParams, "malformed request")
        }
        guard Int(v) == bridgeProtocolVersion else {
            return fail(.versionMismatch, "native speaks v\(bridgeProtocolVersion), got v\(Int(v))")
        }
        guard let handler = handlers[method] else { return fail(.methodNotFound, "unknown method \(method)") }
        do {
            let result = try await handler(request["params"] ?? .null)
            return .object(["v": .number(Double(bridgeProtocolVersion)), "id": .string(id), "result": result])
        } catch let e as BridgeError {
            return .object(["v": .number(Double(bridgeProtocolVersion)), "id": .string(id),
                            "error": .object(["code": .number(Double(e.code)), "message": .string(e.message)])])
        } catch {
            return fail(.internalError, "\(error)")
        }
    }

    /// Builds a native->web request envelope.
    public static func request<P: Encodable>(id: String, method: String, params: P) throws -> JSONValue {
        .object(["v": .number(Double(bridgeProtocolVersion)), "id": .string(id), "method": .string(method), "params": try JSONValue.from(params)])
    }

    /// Unwraps a web->native response, throwing its error if any.
    public static func result<R: Decodable>(_ response: JSONValue, as: R.Type) throws -> R {
        if let err = response["error"] {
            let code: Int = if case .number(let n)? = err["code"] { Int(n) } else { BridgeErrorCode.internalError.rawValue }
            throw BridgeError(code: code, message: err["message"]?.stringValue ?? "unknown error")
        }
        return try (response["result"] ?? .null).decode(as: R.self)
    }
}
