import Foundation

/// The languages Enjin speaks. Everything the kid reads follows this:
/// app screens, the canvas, and what Claude writes.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case en
    case da

    public var id: String { rawValue }

    /// In its own language, for the picker.
    public var displayName: String {
        switch self {
        case .en: "English"
        case .da: "Dansk"
        }
    }

    /// How we name it to a model.
    var promptName: String {
        switch self {
        case .en: "English"
        case .da: "Danish (dansk)"
        }
    }

    /// The device's language if we speak it, else English.
    public static var system: AppLanguage {
        Locale.preferredLanguages.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .en
    }
}

/// Words the kid sees that come from EnjinKit (agent status and errors).
public struct KidStrings: Sendable {
    public var language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    private func t(_ en: String, _ da: String) -> String {
        language == .da ? da : en
    }

    public var needsKey: String { t("Enjin needs a key to think. Ask a parent to add one in Settings.",
                                     "Enjin skal have en nøgle for at kunne tænke. Bed en voksen om at tilføje en under Indstillinger.") }
    public var resting: String { t("Enjin is resting for today. Come back tomorrow!",
                                   "Enjin hviler sig for i dag. Kom tilbage i morgen!") }
    public var refused: String { t("Enjin can't help with that one. Try asking a different way.",
                                   "Det kan Enjin ikke hjælpe med. Prøv at spørge på en anden måde.") }
    public var badKey: String { t("Enjin's key isn't working. Ask a parent to check it in Settings.",
                                  "Enjins nøgle virker ikke. Bed en voksen om at tjekke den under Indstillinger.") }
    public var busy: String { t("Enjin is busy right now. Try again in a moment.",
                                "Enjin har travlt lige nu. Prøv igen om lidt.") }
    public var needsSetup: String { t("Enjin needs setting up. Ask a parent to open Settings and tap Test connection.",
                                      "Enjin skal sættes op. Bed en voksen om at åbne Indstillinger og trykke på Test forbindelse.") }
    public var interrupted: String { t("Enjin got interrupted. Try again.", "Enjin blev afbrudt. Prøv igen.") }
    public var offline: String { t("Can't reach the internet. Try again when you're online.",
                                   "Ingen forbindelse til internettet. Prøv igen, når du er online.") }
    public var generic: String { t("Something went wrong. Try again.", "Noget gik galt. Prøv igen.") }

    public func exploring(_ what: String) -> String { t("Enjin is exploring \(what)…", "Enjin udforsker \(what)…") }
}
