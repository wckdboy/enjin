#if DEBUG
import EnjinKit
import Foundation

/// Deterministic stand-in for the model in UI tests (`-uiTestingFakeAgent`):
/// every turn adds one filled card and one stub, and replies with a fixed line.
struct UITestBackend: AgentBackend {
    let modelId = "ui-test"
    let supportsWebSearch = false
    let isReduced = false

    func run(thread: inout [JSONValue], system: String, tools: [JSONValue],
             onEvent: @escaping @Sendable (ProviderEvent) -> Void,
             execute: @escaping @Sendable (String, JSONValue) async -> ToolOutcome) async throws -> AgentTurnResult {
        try await Task.sleep(for: .milliseconds(300))
        let prompt = thread.last?["content"]?.stringValue ?? ""
        // A fill request names its stub; put the cards inside it.
        let parent = prompt.range(of: #"parentCardId (c-[a-z0-9-]+)"#, options: .regularExpression)
            .map { String(prompt[$0].split(separator: " ").last!) }
        var input: [String: JSONValue] = ["cards": .array([
            .object(["title": .string("Fake fact"), "summary": .string("Something true-ish."), "isStub": .bool(false)]),
            .object(["title": .string("Fake door"), "summary": .string("Dive here next."), "isStub": .bool(true)]),
        ])]
        if let parent { input["parentCardId"] = .string(parent) }
        if let parent {
            _ = await execute("updateCard", .object(["cardId": .string(parent), "summary": .string("Filled by the fake agent."), "state": .string("filled")]))
        }
        onEvent(.toolUse(id: "t1", name: "createCards", input: .object(input), raw: ""))
        _ = await execute("createCards", .object(input))
        onEvent(.textDelta("Here are two cards from the test agent."))
        thread.append(.object(["role": .string("assistant"), "content": .string("ok")]))
        return AgentTurnResult(stop: .done, rounds: 1, usage: .init(), firstEventMs: 300, totalMs: 300)
    }
}
#endif
