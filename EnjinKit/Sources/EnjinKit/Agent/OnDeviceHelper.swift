import Foundation

/// Small, free jobs that don't need Claude: suggesting what to ask next and
/// picking picture search phrases. Runs on Apple's on-device model when
/// available; everything works (with less polish) when it isn't.
public protocol AssistHelper: Sendable {
    /// 2-3 short questions in the kid's voice, for tappable chips.
    func nextQuestions(path: [String], cards: [(title: String, summary: String)], lastAsk: String?, language: AppLanguage) async -> [String]
    /// A short search phrase for a real picture of this card, or nil.
    func imagePhrase(title: String, summary: String, topic: String) async -> String?
}

#if canImport(FoundationModels)
import FoundationModels
import os

@available(iOS 26.0, macOS 26.0, *)
public struct AppleAssistHelper: AssistHelper {
    static let log = Logger(subsystem: "ai.wckd.enjin", category: "assist")
    public init() {}

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @Generable
    struct Questions {
        @Guide(description: "Follow-up questions a curious 13-year-old might ask next, each under 45 characters", .count(3))
        var questions: [String]
    }

    @Generable
    struct Phrase {
        @Guide(description: "A 2-5 word search phrase for a real photo, painting, map or diagram on Wikipedia, or empty if nothing fits")
        var phrase: String
    }

    public func nextQuestions(path: [String], cards: [(title: String, summary: String)], lastAsk: String?, language: AppLanguage) async -> [String] {
        let session = LanguageModelSession(instructions: """
            You suggest what a curious 13-year-old might want to ask next while exploring a topic. \
            Questions are short, concrete, and in the kid's own voice. Don't repeat what the cards already say. \
            Write the questions in \(language.promptName).
            """)
        let list = cards.prefix(8).map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
        let prompt = "Exploring: \(path.joined(separator: " › "))\n\(lastAsk.map { "They just asked: \($0)\n" } ?? "")Cards they can see:\n\(list)"
        let clean = { (qs: [String]) in
            qs.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*0123456789.").union(.whitespacesAndNewlines)) }
                .filter { !$0.isEmpty && $0.count <= 60 }
        }
        do {
            return clean(try await session.respond(to: prompt, generating: Questions.self).content.questions)
        } catch {
            // Structured output can fail in some languages; plain lines work everywhere.
            Self.log.notice("structured questions failed (\(String(describing: error), privacy: .public)); using plain text")
            let plain = LanguageModelSession(instructions: "Write in \(language.promptName). Reply with exactly 3 questions, one per line, nothing else.")
            guard let r = try? await plain.respond(to: prompt + "\n\nWhat might they ask next?") else { return [] }
            return Array(clean(r.content.components(separatedBy: .newlines)).prefix(3))
        }
    }

    public func imagePhrase(title: String, summary: String, topic: String) async -> String? {
        let session = LanguageModelSession(instructions: "You pick search phrases for pictures that help a kid imagine something.")
        let prompt = "Topic: \(topic)\nCard: \(title) — \(summary)\nGive a short search phrase for a real picture of this."
        guard let r = try? await session.respond(to: prompt, generating: Phrase.self) else { return nil }
        let p = r.content.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty || p.count > 60 ? nil : p
    }
}
#endif
