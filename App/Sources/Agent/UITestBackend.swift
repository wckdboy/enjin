#if DEBUG
import EnjinKit
import Foundation
import UIKit

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
            .object(["title": .string("Fake fact"), "summary": .string("Something true-ish."), "isStub": .bool(false), "image": .string("anything")]),
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

/// Pictures for UI tests: a generated gradient, no network.
struct UITestImageFinder: ImageFinder {
    func find(_ query: String, excluding: Set<String>) async throws -> FoundImage? {
        let source = "uitest://\(query)/\(excluding.count)"
        let data = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).pngData { ctx in
                UIColor.systemTeal.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
                UIColor.systemYellow.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 120, y: 50, width: 80, height: 80))
            }
        }
        return FoundImage(data: data, mimeType: "image/png", width: 320, height: 200, credit: "UI test · CC0", sourceURL: source)
    }
}
#endif
