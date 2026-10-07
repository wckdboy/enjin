import EnjinKit
import Foundation
import Observation
import SwiftUI

/// Parent-controlled settings. The API key lives in the Keychain; the rest in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    enum Provider: String, CaseIterable, Identifiable {
        /// Anthropic when a key is set up, otherwise the on-device model.
        case auto
        case anthropic
        case onDevice
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .auto: "Automatic"
            case .anthropic: "Claude (needs key)"
            case .onDevice: "On-device only"
            }
        }
    }

    private let defaults: UserDefaults
    private static let keyAccount = "anthropic"

    var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    var modelId: String { didSet { defaults.set(modelId, forKey: "modelId") } }
    var dailyCapUSD: Double { didSet { defaults.set(dailyCapUSD, forKey: "dailyCapUSD") } }
    /// A parent read and accepted the data/cost notice (plan §7) before any key is used.
    var consentGiven: Bool { didSet { defaults.set(consentGiven, forKey: "consentGiven") } }
    /// For organization keys that aren't scoped to a workspace (wrkspc_...).
    var workspaceId: String { didSet { defaults.set(workspaceId, forKey: "workspaceId") } }
    /// nil = follow the device (Danish if the iPad is in Danish, else English).
    var languageChoice: AppLanguage? { didSet { defaults.set(languageChoice?.rawValue, forKey: "language") } }
    var language: AppLanguage { languageChoice ?? .system }
    var locale: Locale { Locale(identifier: language == .da ? "da_DK" : "en_US") }

    /// Fill stubs in the background while the kid looks at them. Faster dives, more spend.
    var prepareAhead: Bool { didSet { defaults.set(prepareAhead, forKey: "prepareAhead") } }
    /// Real pictures from Wikipedia on Enjin's cards.
    var showPictures: Bool { didSet { defaults.set(showPictures, forKey: "showPictures") } }
    /// The flat card canvas instead of the 3D world (the world is the default).
    var classicCanvas: Bool { didSet { defaults.set(classicCanvas, forKey: "classicCanvas") } }
    /// Enjin chimes in on its own when the explorer lingers on something (Companion).
    var companion: Bool { didSet { defaults.set(companion, forKey: "companion") } }
    /// User.md: how this explorer learns, shared by every notebook.
    let learner = LearnerProfile(url: LearnerProfile.defaultURL())
    private(set) var hasKey: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .auto
        modelId = defaults.string(forKey: "modelId") ?? AnthropicModel.sonnet55.id
        dailyCapUSD = defaults.object(forKey: "dailyCapUSD") as? Double ?? 2
        consentGiven = defaults.bool(forKey: "consentGiven")
        showPictures = defaults.object(forKey: "showPictures") as? Bool ?? true
        workspaceId = defaults.string(forKey: "workspaceId") ?? ""
        prepareAhead = defaults.bool(forKey: "prepareAhead")
        classicCanvas = defaults.bool(forKey: "classicCanvas")
        companion = defaults.object(forKey: "companion") as? Bool ?? true
        languageChoice = defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:))
        hasKey = Keychain.read(Self.keyAccount)?.isEmpty == false
    }

    var model: AnthropicModel { AnthropicModel.all.first { $0.id == modelId } ?? .opus55 }

    /// A tiny real request with the saved key and settings. Nil means it works.
    func testConnection() async -> String? {
        guard let key = Keychain.read(Self.keyAccount), !key.isEmpty else { return "No key saved." }
        return await AnthropicClient(apiKey: key, workspaceId: workspaceId).check(model: model.id)
    }

    func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        Keychain.write(k, account: Self.keyAccount)
        hasKey = true
    }

    func removeKey() {
        Keychain.delete(Self.keyAccount)
        hasKey = false
    }

    var onDeviceUnavailableReason: String? {
        if #available(iOS 26.0, *) { return AppleFMBackend.unavailableReason }
        return "Needs iPadOS 26."
    }

    /// Free on-device help (question chips, picture phrases), when Apple Intelligence is on.
    func makeAssist() -> AssistHelper? {
        if #available(iOS 26.0, *), AppleAssistHelper.isAvailable { return AppleAssistHelper() }
        return nil
    }

    /// Pictures are on: illustrations from Image Playground, one look for everything.
    private static let illustrator = PlaygroundIllustrator()
    func makeIllustrator() -> ImageGenerator? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFakeAgent") { return nil }
        #endif
        return showPictures ? Self.illustrator : nil
    }

    func makeImageFinder() -> ImageFinder? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFakeAgent") { return UITestImageFinder() }
        #endif
        return showPictures ? WikimediaImages() : nil
    }

    func makeBackend() -> AgentBackend? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFakeAgent") { return UITestBackend() }
        #endif
        let key = consentGiven ? Keychain.read(Self.keyAccount) : nil
        let claude = key.flatMap { $0.isEmpty ? nil : AnthropicBackend(apiKey: $0, workspaceId: workspaceId, model: model) }
        let onDevice: AgentBackend? = {
            if #available(iOS 26.0, *), AppleFMBackend.unavailableReason == nil { return AppleFMBackend() }
            return nil
        }()
        switch provider {
        case .anthropic: return claude
        case .onDevice: return onDevice
        case .auto: return claude ?? onDevice
        }
    }

    /// The small, cheap model for small jobs (the companion, writing a card on demand): Haiku, on the same
    /// key, whenever Claude is in use. Nil otherwise (they fall back to the main backend).
    func makeLightBackend() -> AgentBackend? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFakeAgent") { return nil }
        #endif
        guard let main = makeBackend() as? AnthropicBackend, main.model != .haiku45,
              let key = Keychain.read(Self.keyAccount), !key.isEmpty else { return nil }
        return AnthropicBackend(apiKey: key, workspaceId: workspaceId, model: .haiku45, effort: nil)
    }

    /// One line for the parent: what Enjin will actually use right now.
    var activeDescription: LocalizedStringKey {
        guard let b = makeBackend() else {
            if provider == .onDevice, let reason = onDeviceUnavailableReason { return LocalizedStringKey(reason) }
            return "Not set up: add a key, or use an iPad with Apple Intelligence."
        }
        return b.isReduced ? "Apple on-device model (no web search, simpler answers)" : "Claude \(model.label) with web search"
    }
}
