import Foundation
import Observation

/// User.md: what Enjin has learned about how this explorer learns, kept across
/// every notebook. Enjin reads it every turn and adds to it (the
/// rememberAboutLearner tool) when it notices something that lasts: which
/// visuals click, what they're curious about, their pace, what to avoid. The
/// explorer can read and edit it in Settings; it's theirs.
///
/// Only learning matters go in here: never names, places, schools or anything
/// else that identifies someone.
@MainActor
@Observable
public final class LearnerProfile {
    public enum Section: String, CaseIterable, Codable, Sendable {
        case learning = "How I learn best"
        case visuals = "Visuals that work for me"
        case curious = "What I'm curious about"
        case level = "Level and pace"
        case avoid = "What doesn't work for me"
    }

    public static let maxNotesPerSection = 8
    public static let maxNoteLength = 200

    /// The file as the explorer sees it.
    public private(set) var markdown: String
    @ObservationIgnored private var notes: [Section: [String]] = [:]
    @ObservationIgnored private let url: URL?

    /// `url` nil keeps it in memory (tests, previews).
    public init(url: URL?) {
        self.url = url
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        notes = Self.parse(text)
        markdown = Self.render(notes)
    }

    /// Where it lives: Application Support/Enjin/User.md.
    public static func defaultURL() -> URL? {
        // UI tests start from nothing, like a fresh install.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFreshStore") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("uitest-User-\(UUID().uuidString).md")
        }
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Enjin", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("User.md")
    }

    public var isEmpty: Bool { notes.values.allSatisfy(\.isEmpty) }

    public func notes(in section: Section) -> [String] { notes[section] ?? [] }

    /// Add a note (or replace one that's no longer true). Oldest notes make room when a section is full.
    @discardableResult
    public func remember(_ note: String, in section: Section, replacing old: String? = nil) -> Bool {
        let text = Self.clean(note)
        guard !text.isEmpty else { return false }
        var list = notes[section] ?? []
        if let old = old.map(Self.clean), let i = list.firstIndex(where: { $0.caseInsensitiveCompare(old) == .orderedSame }) {
            list[i] = text
        } else if list.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
            return true
        } else {
            list.append(text)
        }
        if list.count > Self.maxNotesPerSection { list.removeFirst(list.count - Self.maxNotesPerSection) }
        notes[section] = list
        save()
        return true
    }

    /// The explorer edited the file by hand.
    public func replace(with markdown: String) {
        notes = Self.parse(markdown)
        save()
    }

    public func reset() {
        notes = [:]
        save()
    }

    /// For the prompt: the notes, or a line saying there are none yet.
    public var promptText: String {
        isEmpty ? "Nothing yet: you're still getting to know them. Watch what they do and notice what works."
            : Self.render(notes, header: false)
    }

    private func save() {
        markdown = Self.render(notes)
        guard let url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Format

    static func clean(_ s: String) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let bare = one.hasPrefix("- ") ? String(one.dropFirst(2)) : one
        return String(bare.prefix(maxNoteLength)).trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ text: String) -> [Section: [String]] {
        var out: [Section: [String]] = [:]
        var current: Section?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                current = Section.allCases.first { $0.rawValue.caseInsensitiveCompare(title) == .orderedSame }
                continue
            }
            guard let section = current else { continue }
            let note = clean(line)
            if !note.isEmpty && (out[section]?.count ?? 0) < maxNotesPerSection { out[section, default: []].append(note) }
        }
        return out
    }

    static func render(_ notes: [Section: [String]], header: Bool = true) -> String {
        var lines: [String] = header ? ["# User.md", "", "What Enjin has learned about how you learn. Edit anything; Enjin reads it every time.", ""] : []
        for section in Section.allCases {
            let list = notes[section] ?? []
            if !header && list.isEmpty { continue }
            lines.append("## \(section.rawValue)")
            lines += list.map { "- \($0)" }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
