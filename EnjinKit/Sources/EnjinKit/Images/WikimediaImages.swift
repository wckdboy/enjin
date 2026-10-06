import Foundation

public struct FoundImage: Sendable, Equatable {
    public var data: Data
    public var mimeType: String
    public var width: Int
    public var height: Int
    public var credit: String?
    /// Stable identity of the picture (its Commons page), for not repeating it.
    public var sourceURL: String

    public init(data: Data, mimeType: String, width: Int, height: Int, credit: String?, sourceURL: String) {
        self.data = data; self.mimeType = mimeType; self.width = width; self.height = height; self.credit = credit; self.sourceURL = sourceURL
    }
}

/// Finds a real picture for a phrase. Swappable for tests and UI tests.
public protocol ImageFinder: Sendable {
    func find(_ query: String, excluding: Set<String>) async throws -> FoundImage?
}

/// Pictures from Wikipedia: the lead image of the best-matching articles,
/// free-licensed only, with attribution, and a keyword safety screen.
public struct WikimediaImages: ImageFinder {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    let fetch: Fetch
    let host: String
    let thumbWidth: Int

    public init(language: String = "en", thumbWidth: Int = 640, fetch: Fetch? = nil) {
        host = "\(language).wikipedia.org"
        self.thumbWidth = thumbWidth
        self.fetch = fetch ?? { url in
            var req = URLRequest(url: url, timeoutInterval: 15)
            // Wikimedia asks API clients to identify themselves.
            req.setValue("Enjin/0.1 (iPad learning app for kids)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// Words that keep a picture off a kid's canvas, checked against the article
    /// title, file name, description and Commons categories.
    static let blocked = [
        "nude", "naked", "nudity", "erotic", "sexual", "genital", "penis", "vulva", "vagina", "topless", "pornograph",
        "corpse", "cadaver", "dead body", "decapitat", "beheading", "lynching", "torture", "autopsy", "gore", "mutilat",
        "execution of", "hanged", "massacre victims",
    ]

    static func isBlocked(_ texts: [String]) -> Bool {
        let hay = texts.joined(separator: " ").lowercased()
        return blocked.contains { hay.contains($0) }
    }

    public func find(_ query: String, excluding: Set<String>) async throws -> FoundImage? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var search = URLComponents(string: "https://\(host)/w/api.php")!
        search.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "search"), .init(name: "gsrsearch", value: q), .init(name: "gsrlimit", value: "6"),
            .init(name: "gsrnamespace", value: "0"), .init(name: "prop", value: "pageimages"),
            .init(name: "piprop", value: "thumbnail|name"), .init(name: "pithumbsize", value: "\(thumbWidth)"),
            .init(name: "pilicense", value: "free"),
        ]
        let json = try JSONDecoder().decode(JSONValue.self, from: try await fetch(search.url!))
        guard case .array(let pages)? = json["query"]?["pages"] else { return nil }
        // Search rank order.
        let ranked = pages.sorted { ($0["index"]?.intValue ?? 99) < ($1["index"]?.intValue ?? 99) }

        for page in ranked {
            guard let thumb = page["thumbnail"], let src = thumb["source"]?.stringValue, let file = page["pageimage"]?.stringValue,
                  let w = thumb["width"]?.intValue, let h = thumb["height"]?.intValue, min(w, h) >= 160 else { continue }
            let title = page["title"]?.stringValue ?? ""
            if Self.isBlocked([title, file]) { continue }

            let info = try? await fileInfo(file)
            if let info, Self.isBlocked([info.description, info.categories]) { continue }
            let commons = info?.pageURL ?? "https://commons.wikimedia.org/wiki/File:\(file)"
            if excluding.contains(commons) { continue }

            guard let data = try? await fetch(URL(string: src)!) else { continue }
            let mime = src.lowercased().hasSuffix(".png") || src.lowercased().contains(".svg") ? "image/png" : "image/jpeg"
            return FoundImage(data: data, mimeType: mime, width: w, height: h, credit: info?.credit, sourceURL: commons)
        }
        return nil
    }

    struct FileInfo {
        var credit: String?
        var description: String
        var categories: String
        var pageURL: String?
    }

    func fileInfo(_ file: String) async throws -> FileInfo {
        var c = URLComponents(string: "https://\(host)/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "titles", value: "File:\(file)"), .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "extmetadata|url"),
        ]
        let json = try JSONDecoder().decode(JSONValue.self, from: try await fetch(c.url!))
        guard case .array(let pages)? = json["query"]?["pages"], case .array(let infos)? = pages.first?["imageinfo"], let info = infos.first else {
            return FileInfo(credit: nil, description: "", categories: "", pageURL: nil)
        }
        let meta = info["extmetadata"]
        func field(_ k: String) -> String { Self.stripHTML(meta?[k]?["value"]?.stringValue ?? "") }
        let artist = field("Artist")
        let license = field("LicenseShortName")
        let credit = [artist.isEmpty ? nil : String(artist.prefix(80)), license.isEmpty ? nil : license].compactMap { $0 }.joined(separator: " · ")
        return FileInfo(credit: credit.isEmpty ? nil : credit, description: field("ImageDescription"), categories: field("Categories"),
                        pageURL: info["descriptionurl"]?.stringValue)
    }

    static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
