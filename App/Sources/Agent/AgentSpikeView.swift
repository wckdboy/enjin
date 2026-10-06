import EnjinKit
import SwiftUI

/// M0 spike #4: one real streamed turn with a custom tool + web search, with the
/// numbers we need to choose a model (first-event latency, total, tokens, cache).
struct AgentSpikeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = Keychain.read("anthropic") ?? ""
    @State private var model: AnthropicModel = .opus55
    @State private var prompt = "Why did the Roman legions win so many battles?"
    @State private var log: [String] = []
    @State private var cards: [String] = []
    @State private var result: AgentTurnResult?
    @State private var running: Task<Void, Never>?
    @State private var error: String?
    @State private var streamedText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Key (stored in Keychain, this device only)") {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .onSubmit { Keychain.write(apiKey, account: "anthropic") }
                }
                Section("Turn") {
                    Picker("Model", selection: $model) {
                        ForEach(AnthropicModel.all) { Text($0.label).tag($0) }
                    }
                    TextField("Prompt", text: $prompt, axis: .vertical)
                    Button(running == nil ? "Run" : "Cancel", action: toggle)
                        .disabled(apiKey.isEmpty)
                }
                if let r = result {
                    Section("Numbers") {
                        LabeledContent("First event", value: r.firstEventMs.map { String(format: "%.0f ms", $0) } ?? "–")
                        LabeledContent("Total", value: String(format: "%.0f ms", r.totalMs))
                        LabeledContent("Rounds / stop", value: "\(r.rounds) / \(String(describing: r.stop))")
                        LabeledContent("Tokens in / out", value: "\(r.usage.inputTokens) / \(r.usage.outputTokens)")
                        LabeledContent("Cache read / write", value: "\(r.usage.cacheReadInputTokens) / \(r.usage.cacheCreationInputTokens)")
                    }
                }
                if let error { Section("Error") { Text(error).foregroundStyle(.red) } }
                if !cards.isEmpty { Section("createCards calls") { ForEach(cards, id: \.self) { Text($0).font(.callout.monospaced()) } } }
                Section("Stream") {
                    ForEach(Array(log.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
                }
            }
            .navigationTitle("Agent spike")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func toggle() {
        if let running {
            running.cancel()
            self.running = nil
            return
        }
        Keychain.write(apiKey, account: "anthropic")
        log = []; cards = []; result = nil; error = nil
        let loop = AgentLoop(client: AnthropicClient(apiKey: apiKey), config: SpikeAgent.config(model: model))
        let input = prompt
        running = Task {
            var messages: [JSONValue] = [.object(["role": .string("user"), "content": .string(input)])]
            do {
                let r = try await loop.run(messages: &messages, onEvent: { e in
                    Task { @MainActor in
                        switch e {
                        case .textDelta(let t): streamedText += t
                        case .serverToolUse(let name, let input): log.append("🔎 \(name) \(input["query"]?.stringValue ?? "")")
                        case .webSearchResults(let rs): log.append("   \(rs.count) results: \(rs.prefix(3).map(\.title).joined(separator: " · "))")
                        case .webSearchError(let code): log.append("   search error: \(code)")
                        case .citation(let r, _): log.append("   cites \(r.url)")
                        case .toolUse(_, let name, let input, _): log.append("🛠 \(name) \(input == nil ? "(invalid JSON)" : "")")
                        case .stop(let reason): log.append("■ \(reason)  \(streamedText.prefix(400))"); streamedText = ""
                        }
                    }
                }, executeTool: { name, input in
                    guard name == "createCards", case .array(let list)? = input["cards"] else { return .error("unknown tool or bad input") }
                    let titles = list.compactMap { $0["title"]?.stringValue }
                    await MainActor.run { cards.append(contentsOf: titles) }
                    return .ok(#"{"created": \#(titles.count)}"#)
                })
                result = r
            } catch is CancellationError {
                log.append("cancelled")
            } catch {
                self.error = error.localizedDescription
            }
            running = nil
        }
    }
}

enum SpikeAgent {
    static let system = """
    You are Enjin, a mentor for a curious 13-year-old exploring a topic on a canvas of cards.
    Answer briefly and concretely first. Use web search for factual claims and cite sources.
    Put what you learn on the canvas with createCards: at most 4 cards, title <= 60 chars, \
    summary <= 140 chars. Mark follow-up directions as stubs (isStub: true) so the kid can dive into them.
    If sources disagree, say so plainly in the card summary.
    """

    static let createCards: JSONValue = .object([
        "name": .string("createCards"),
        "description": .string("Add cards to the kid's canvas in the current portal."),
        "input_schema": .object([
            "type": .string("object"),
            "properties": .object([
                "cards": .object([
                    "type": .string("array"),
                    "maxItems": .number(4),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object(["type": .string("string")]),
                            "summary": .object(["type": .string("string")]),
                            "isStub": .object(["type": .string("boolean")]),
                        ]),
                        "required": .array([.string("title"), .string("summary"), .string("isStub")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("cards")]),
        ]),
    ])

    static func config(model: AnthropicModel) -> AgentConfig {
        var c = AgentConfig(model: model, system: system, tools: [createCards], effort: "low")
        c.blockedDomains = ["pornhub.com", "xvideos.com", "onlyfans.com", "bet365.com", "4chan.org"]
        return c
    }
}
