import Foundation
import Testing
@testable import EnjinKit

/// Decodes every shared bridge fixture with the Swift types and re-encodes it.
/// Fails if web adds/renames a field Swift doesn't know (or vice versa).
@MainActor
struct ContractTests {
    nonisolated static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/bridge-fixtures")

    struct Fixture: Decodable {
        var direction: String
        var request: JSONValue
        var response: JSONValue
    }

    static func load(_ method: String) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtures.appendingPathComponent("\(method).json")))
    }

    /// JSON null and a missing key mean the same thing to both sides.
    static func normalized(_ v: JSONValue) -> JSONValue {
        switch v {
        case .object(let o): .object(o.filter { $0.value != .null }.mapValues(normalized))
        case .array(let a): .array(a.map(normalized))
        default: v
        }
    }

    func roundTrip<P: Codable, R: Codable>(_ method: String, _ p: P.Type, _ r: R.Type) throws {
        let fx = try Self.load(method)
        let params = try (fx.request["params"] ?? .null).decode(as: P.self)
        #expect(Self.normalized(try JSONValue.from(params)) == Self.normalized(fx.request["params"]!), "params drift in \(method)")
        let result = try BridgeRouter.result(fx.response, as: R.self)
        #expect(Self.normalized(try JSONValue.from(result)) == Self.normalized(fx.response["result"] ?? .null), "result drift in \(method)")
    }

    @Test func everyMethodHasAFixtureAndATest() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasSuffix(".json") }
        let methods = Set(files.map { String($0.dropLast(5)) })
        #expect(methods == [
            "portal.load", "ink.lock", "ink.commit", "canvas.flash", "canvas.applyOps", "canvas.frame",
            "canvas.ready", "canvas.changed", "focus.changed", "selection.changed", "portal.enter", "portal.exit", "log.event",
        ])
    }

    @Test func nativeToWeb() throws {
        try roundTrip("portal.load", NativeMethod.PortalLoad.self, Empty?.self)
        try roundTrip("ink.lock", NativeMethod.InkLock.self, Empty?.self)
        try roundTrip("ink.commit", NativeMethod.InkCommit.self, NativeMethod.InkCommitResult.self)
        try roundTrip("canvas.flash", NativeMethod.CanvasFlash.self, Empty?.self)
        try roundTrip("canvas.frame", NativeMethod.CanvasFrame.self, NativeMethod.CanvasFrameResult.self)
        try roundTrip("canvas.applyOps", NativeMethod.ApplyOps.self, NativeMethod.ApplyOpsResult.self)
    }

    @Test func webToNative() throws {
        try roundTrip("canvas.ready", WebMethod.CanvasReady.self, WebMethod.CanvasReadyResult.self)
        try roundTrip("canvas.changed", WebMethod.CanvasChanged.self, Empty?.self)
        try roundTrip("focus.changed", WebMethod.FocusChanged.self, Empty?.self)
        try roundTrip("selection.changed", WebMethod.SelectionChanged.self, Empty?.self)
        try roundTrip("portal.enter", WebMethod.PortalEnter.self, PortalScene?.self)
        try roundTrip("portal.exit", WebMethod.PortalExit.self, WebMethod.PortalExitResult?.self)
        try roundTrip("log.event", WebMethod.LogEvent.self, Empty?.self)
    }

    @Test func routerDispatchesFixtureRequests() async throws {
        let router = BridgeRouter()
        router.on("portal.enter", WebMethod.PortalEnter.self) { p in
            #expect(p.cardId == "c-legions")
            return try Self.load("portal.enter").response["result"]!.decode(as: PortalScene.self)
        }
        let res = await router.handle(try Self.load("portal.enter").request)
        #expect(res["error"] == nil)
        #expect(try BridgeRouter.result(res, as: PortalScene.self).portalId == "p-legions")
    }

    @Test func routerErrors() async throws {
        let router = BridgeRouter()
        router.on("portal.exit", WebMethod.PortalExit.self) { _ in Empty() }
        func code(_ req: JSONValue) async -> Double? {
            if case .number(let n)? = await router.handle(req)["error"]?["code"] { n } else { nil }
        }
        #expect(await code(.object(["v": .number(1), "id": .string("a"), "method": .string("nope"), "params": .object([:])])) == -32601)
        #expect(await code(.object(["v": .number(2), "id": .string("b"), "method": .string("portal.exit"), "params": .object([:])])) == -32000)
        #expect(await code(.object(["v": .number(1), "id": .string("c"), "method": .string("portal.exit"), "params": .object([:])])) == -32602)
    }
}
