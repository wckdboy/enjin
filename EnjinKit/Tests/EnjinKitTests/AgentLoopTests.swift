import Foundation
import Testing
@testable import EnjinKit

/// Serves canned SSE responses in order and records request bodies.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String] = []
    nonisolated(unsafe) static var bodies: [JSONValue] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody
        if data == nil, let s = request.httpBodyStream {
            s.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            data = d
        }
        let body = String(Self.lock.withLock { () -> String in
            if let data, let json = try? JSONDecoder().decode(JSONValue.self, from: data) { Self.bodies.append(json) }
            return Self.responses.isEmpty ? "" : Self.responses.removeFirst()
        })
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func sse(_ events: [String]) -> String { events.map { "data: \($0)\n\n" }.joined() }

    static func toolTurn(text: String, toolInput: String) -> String {
        sse([
            #"{"type":"message_start","message":{"id":"m","usage":{"input_tokens":10,"output_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"createCards","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":\#(JSONValue.string(toolInput).jsonString)}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":50}}"#,
            #"{"type":"message_stop"}"#,
        ])
    }

    static let endTurn = sse([
        #"{"type":"message_start","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"fixed"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#,
        #"{"type":"message_stop"}"#,
    ])
}

@Suite(.serialized)
struct AgentLoopTests {
    func loop() -> AgentLoop {
        var client = AnthropicClient(apiKey: "k")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        client.session = URLSession(configuration: cfg)
        var config = AgentConfig(model: .opus55, system: "s", tools: AgentTools.all)
        config.endAfterClientTools = true
        return AgentLoop(client: client, config: config)
    }

    @Test func endsAfterSuccessfulClientToolsInOneRound() async throws {
        StubProtocol.lock.withLock { StubProtocol.responses = [StubProtocol.toolTurn(text: "Here you go.", toolInput: #"{"cards":[]}"#)]; StubProtocol.bodies = [] }
        var messages: [JSONValue] = [.object(["role": .string("user"), "content": .string("hi")])]
        let r = try await loop().run(messages: &messages, onEvent: { _ in }, executeTool: { _, _ in .ok("Added 0 cards.") })
        #expect(r.rounds == 1)
        #expect(StubProtocol.bodies.count == 1, "no second request just to say done")
        #expect(r.pendingToolResults.count == 1)
        #expect(r.pendingToolResults.first?["tool_use_id"] == .string("toolu_1"))
        #expect(messages.last?["role"] == .string("assistant"), "thread ends on the assistant's tool call")
    }

    @Test func aFailedToolStillGetsARetryRound() async throws {
        StubProtocol.lock.withLock { StubProtocol.responses = [StubProtocol.toolTurn(text: "", toolInput: #"{"cards":[]}"#), StubProtocol.endTurn]; StubProtocol.bodies = [] }
        var messages: [JSONValue] = [.object(["role": .string("user"), "content": .string("hi")])]
        let r = try await loop().run(messages: &messages, onEvent: { _ in }, executeTool: { _, _ in .error("nope") })
        #expect(r.rounds == 2)
        #expect(r.pendingToolResults.isEmpty)
        // The second request carried the error result.
        guard case .array(let msgs)? = StubProtocol.bodies.last?["messages"], case .array(let blocks)? = msgs.last?["content"] else {
            Issue.record("no second request"); return
        }
        #expect(blocks.first?["is_error"] == .bool(true))
    }
}
