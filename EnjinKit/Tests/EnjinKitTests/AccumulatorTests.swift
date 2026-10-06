import Foundation
import Testing
@testable import EnjinKit

/// Replays hand-written SSE in the documented Messages API stream shapes.
struct AccumulatorTests {
    static let sse = #"""
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"usage":{"input_tokens":120,"output_tokens":1,"cache_read_input_tokens":100}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}
    data: {"type":"content_block_stop","index":0}
    data: {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}
    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"roman leg"}}
    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ions\"}"}}
    data: {"type":"content_block_stop","index":1}
    data: {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"Roman legion","url":"https://en.wikipedia.org/wiki/Roman_legion","encrypted_content":"x"}]}}
    data: {"type":"content_block_stop","index":2}
    data: {"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}
    data: {"type":"content_block_delta","index":3,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://en.wikipedia.org/wiki/Roman_legion","title":"Roman legion","cited_text":"about 5,000 men","encrypted_index":"e"}}}
    data: {"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"A legion had about 5,000 men."}}
    data: {"type":"content_block_stop","index":3}
    data: {"type":"content_block_start","index":4,"content_block":{"type":"tool_use","id":"toolu_1","name":"createCards","input":{}}}
    data: {"type":"content_block_delta","index":4,"delta":{"type":"input_json_delta","partial_json":"{\"cards\":[{\"title\":\"Legions\"}]}"}}
    data: {"type":"content_block_stop","index":4}
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":88}}
    data: {"type":"message_stop"}
    """#

    @Test func rebuildsEveryBlockForEchoBack() throws {
        var acc = MessageAccumulator()
        var events: [ProviderEvent] = []
        for line in Self.sse.split(separator: "\n") {
            if let e = try SSE.event(fromLine: line) { events += try acc.apply(e) }
        }
        #expect(acc.stopReason == "tool_use")
        #expect(acc.usage.outputTokens == 88)
        #expect(acc.usage.cacheReadInputTokens == 100)
        #expect(acc.content.count == 5)
        #expect(acc.content[0]["signature"] == .string("sig123"))
        #expect(acc.content[1]["input"]?["query"] == .string("roman legions"))
        #expect(acc.content[3]["citations"].map { if case .array(let a) = $0 { a.count } else { 0 } } == 1)
        #expect(acc.content[4]["input"]?["cards"] != nil)

        let legion = ProviderEvent.WebResult(title: "Roman legion", url: "https://en.wikipedia.org/wiki/Roman_legion")
        #expect(events.contains(.serverToolUse(name: "web_search", input: .object(["query": .string("roman legions")]))))
        #expect(events.contains(.webSearchResults([legion])))
        #expect(events.contains(.citation(legion, citedText: "about 5,000 men")))
        #expect(events.contains(.textDelta("A legion had about 5,000 men.")))
        #expect(events.last == .stop(reason: "tool_use"))
    }

    @Test func invalidToolJSONIsReportedNotDropped() throws {
        var acc = MessageAccumulator()
        _ = try acc.apply(.object(["type": .string("content_block_start"), "index": .number(0),
                                   "content_block": .object(["type": .string("tool_use"), "id": .string("t"), "name": .string("createCards"), "input": .object([:])])]))
        _ = try acc.apply(.object(["type": .string("content_block_delta"), "index": .number(0),
                                   "delta": .object(["type": .string("input_json_delta"), "partial_json": .string("{\"cards\": [")])]))
        let out = try acc.apply(.object(["type": .string("content_block_stop"), "index": .number(0)]))
        #expect(out == [.toolUse(id: "t", name: "createCards", input: nil, raw: "{\"cards\": [")])
    }

    @Test func webSearchErrorObject() throws {
        var acc = MessageAccumulator()
        let out = try acc.apply(.object(["type": .string("content_block_start"), "index": .number(0), "content_block": .object([
            "type": .string("web_search_tool_result"), "tool_use_id": .string("s"),
            "content": .object(["type": .string("web_search_tool_result_error"), "error_code": .string("max_uses_exceeded")]),
        ])]))
        #expect(out == [.webSearchError("max_uses_exceeded")])
    }

    @Test func streamErrorThrows() {
        var acc = MessageAccumulator()
        #expect(throws: AnthropicError.stream(type: "overloaded_error", message: "Overloaded")) {
            _ = try acc.apply(.object(["type": .string("error"), "error": .object(["type": .string("overloaded_error"), "message": .string("Overloaded")])]))
        }
    }

    @Test func requestBodyPerModel() {
        let tool: JSONValue = .object(["name": .string("createCards"), "description": .string("d"), "input_schema": .object(["type": .string("object")])])
        let opus = AgentLoop(client: AnthropicClient(apiKey: "k"), config: AgentConfig(model: .opus55, system: "s", tools: [tool]))
        let (b, betas) = opus.body(messages: [])
        #expect(betas == ["server-side-fallback-2026-07-01"])
        #expect(b["fallbacks"] == .string("default"))
        #expect(b["output_config"]?["effort"] == .string("low"))
        guard case .array(let tools)? = b["tools"] else { Issue.record("no tools"); return }
        #expect(tools[0]["eager_input_streaming"] == .bool(true))
        #expect(tools[1]["type"] == .string("web_search_20260209"))
        #expect(tools[1]["eager_input_streaming"] == nil)

        let haiku = AgentLoop(client: AnthropicClient(apiKey: "k"), config: AgentConfig(model: .haiku45, system: "s", tools: [tool]))
        let (hb, hbetas) = haiku.body(messages: [])
        #expect(hbetas.isEmpty)
        #expect(hb["output_config"] == nil)
        #expect(hb["fallbacks"] == nil)
    }
}
