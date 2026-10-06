import Foundation
import os

public enum StoreError: Error, Equatable, LocalizedError {
    case notFound(String)
    case newerSchema(file: String, found: Int, supported: Int)
    case noMigration(file: String, from: Int)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "Notebook \(id) not found"
        case .newerSchema(let f, let found, let supported): "\(f) was saved by a newer Enjin (schema \(found), this app reads \(supported))"
        case .noMigration(let f, let from): "No migration for \(f) from schema \(from)"
        case .io(let m): m
        }
    }
}

/// Notebooks as plain JSON files (plan §6):
///
///     <root>/<notebookId>/notebook.json  portals.json  cards.json  scenes/<portalId>.json
///
/// Every write is temp file -> fsync -> rename, so a crash leaves either the old
/// file or the new one, never a torn one. The actor serializes all writes.
public actor NotebookStore {
    public static let schemaVersion = 1

    /// Upgrades a file's JSON from `key` to `key + 1`. Applied in order on load;
    /// the notebook is backed up before the first migrated write.
    public typealias Migration = @Sendable (_ file: String, _ json: JSONValue) throws -> JSONValue

    public let root: URL
    private let migrations: [Int: Migration]
    private let supportedVersion: Int
    private let log = Logger(subsystem: "cc.wckd.enjin", category: "store")

    public init(root: URL, schemaVersion: Int = NotebookStore.schemaVersion, migrations: [Int: Migration] = [:]) {
        self.root = root
        self.supportedVersion = schemaVersion
        self.migrations = migrations
    }

    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Notebooks", isDirectory: true)
    }

    // MARK: - Notebooks

    public func list() -> [NotebookMeta] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir -> NotebookMeta? in
            guard !dir.lastPathComponent.hasPrefix("."), !dir.lastPathComponent.contains(".backup-") else { return nil }
            do {
                return try read(dir.appendingPathComponent("notebook.json"), key: "notebook", as: NotebookMeta.self)
            } catch {
                log.error("skipping unreadable notebook \(dir.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func load(_ id: String) throws -> NotebookData {
        let dir = dir(id)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("notebook.json").path) else { throw StoreError.notFound(id) }
        removeStrayTempFiles(in: dir)
        return NotebookData(
            meta: try read(dir.appendingPathComponent("notebook.json"), key: "notebook", as: NotebookMeta.self),
            cards: try read(dir.appendingPathComponent("cards.json"), key: "cards", as: [StoredCard].self),
            portals: try read(dir.appendingPathComponent("portals.json"), key: "portals", as: [Portal].self))
    }

    public func save(_ data: NotebookData) throws {
        try saveCards(data.meta.id, data.cards)
        try savePortals(data.meta.id, data.portals)
        try saveMeta(data.meta)
    }

    public func saveMeta(_ meta: NotebookMeta) throws {
        try write(meta, key: "notebook", to: dir(meta.id).appendingPathComponent("notebook.json"))
    }

    public func saveCards(_ id: String, _ cards: [StoredCard]) throws {
        try write(cards, key: "cards", to: dir(id).appendingPathComponent("cards.json"))
    }

    public func savePortals(_ id: String, _ portals: [Portal]) throws {
        try write(portals, key: "portals", to: dir(id).appendingPathComponent("portals.json"))
    }

    public func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: dir(id))
    }

    // MARK: - Scenes

    public func scene(_ id: String, portalId: String) throws -> [JSONValue] {
        let url = sceneURL(id, portalId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try read(url, key: "elements", as: [JSONValue].self)
    }

    public func saveScene(_ id: String, portalId: String, elements: [JSONValue]) throws {
        try write(elements, key: "elements", to: sceneURL(id, portalId))
    }

    // MARK: - Binary files (card images)

    public func saveFile(_ id: String, fileId: String, data: Data) throws {
        try Self.atomicWrite(data, to: dir(id).appendingPathComponent("files", isDirectory: true).appendingPathComponent(fileId))
    }

    public func file(_ id: String, fileId: String) -> Data? {
        try? Data(contentsOf: dir(id).appendingPathComponent("files", isDirectory: true).appendingPathComponent(fileId))
    }

    /// A picture for the notebook's cover: the first card picture on its top
    /// canvas, else any card picture. Nil for notebooks without pictures yet.
    public func cover(_ id: String) -> Data? {
        guard let data = try? load(id) else { return nil }
        let withImages = data.cards.filter { $0.isActive && $0.image != nil }
        let pick = withImages.first { $0.portalId == data.meta.rootPortalId } ?? withImages.first
        return pick?.image.flatMap { file(id, fileId: $0.fileId) }
    }

    /// Active cards in a notebook (for "12 cards" on its cover).
    public func cardCount(_ id: String) -> Int {
        ((try? load(id))?.cards.filter(\.isActive).count) ?? 0
    }

    // MARK: - Files

    private func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

    private func sceneURL(_ id: String, _ portalId: String) -> URL {
        dir(id).appendingPathComponent("scenes", isDirectory: true).appendingPathComponent("\(portalId).json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(StoreDate.format(date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = StoreDate.parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }()

    /// Files are `{"schemaVersion": n, "<key>": value}`.
    private func write<T: Encodable>(_ value: T, key: String, to url: URL) throws {
        let body = JSONValue.object(["schemaVersion": .number(Double(supportedVersion)), key: try Self.decoder.decode(JSONValue.self, from: Self.encoder.encode(value))])
        try Self.atomicWrite(Self.encoder.encode(body), to: url)
    }

    private func read<T: Decodable>(_ url: URL, key: String, as: T.Type) throws -> T {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw StoreError.io("\(url.lastPathComponent): \(error.localizedDescription)") }
        var json = try Self.decoder.decode(JSONValue.self, from: data)
        var version = json["schemaVersion"]?.intValue ?? 0
        let file = url.lastPathComponent
        if version > supportedVersion { throw StoreError.newerSchema(file: file, found: version, supported: supportedVersion) }
        if version < supportedVersion {
            try backupOnce(notebookDir: url.pathComponents.contains("scenes") ? url.deletingLastPathComponent().deletingLastPathComponent() : url.deletingLastPathComponent(), from: version)
            while version < supportedVersion {
                guard let migrate = migrations[version] else { throw StoreError.noMigration(file: file, from: version) }
                json = try migrate(file, json)
                version += 1
            }
            log.info("migrated \(file) to schema \(version)")
        }
        return try Self.decoder.decode(T.self, from: Self.encoder.encode(json[key] ?? .null))
    }

    /// Copy the whole notebook aside before the first migration touches it.
    private func backupOnce(notebookDir: URL, from version: Int) throws {
        let backup = notebookDir.deletingLastPathComponent().appendingPathComponent("\(notebookDir.lastPathComponent).backup-v\(version)")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.copyItem(at: notebookDir, to: backup)
    }

    private func removeStrayTempFiles(in dir: URL) {
        let fm = FileManager.default
        for sub in [dir, dir.appendingPathComponent("scenes")] {
            for f in (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasSuffix(".tmp") {
                try? fm.removeItem(at: f)
            }
        }
    }

    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: tmp.path, contents: nil) else { throw StoreError.io("cannot create \(tmp.lastPathComponent)") }
        do {
            let h = try FileHandle(forWritingTo: tmp)
            defer { try? h.close() }
            try h.write(contentsOf: data)
            try h.synchronize()
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        guard rename(tmp.path, url.path) == 0 else {
            let err = String(cString: strerror(errno))
            try? fm.removeItem(at: tmp)
            throw StoreError.io("rename \(url.lastPathComponent): \(err)")
        }
    }
}

/// ISO-8601 UTC with exactly three fractional digits, built from integer
/// milliseconds so formatting never truncates and parsing round-trips exactly.
enum StoreDate {
    static func format(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = Date(timeIntervalSince1970: TimeInterval(ms.quotient(1000)))
        // "2026-10-06T15:35:08Z" -> "2026-10-06T15:35:08.726Z"
        return String(seconds.formatted(.iso8601).dropLast()) + String(format: ".%03lldZ", ms.remainder(1000))
    }

    static func parse(_ s: String) -> Date? {
        let (whole, fraction): (Substring, Int64) = {
            guard let dot = s.firstIndex(of: "."), s.hasSuffix("Z"), let f = Int64(s[s.index(after: dot)..<s.index(before: s.endIndex)]) else {
                return (Substring(s), 0)
            }
            return (s[..<dot] + "Z", f)
        }()
        guard let base = try? Date(String(whole), strategy: .iso8601) else { return nil }
        let ms = Int64(base.timeIntervalSince1970.rounded()) * 1000 + fraction
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

private extension Int64 {
    /// Floor division, so dates before 1970 still split correctly.
    func quotient(_ d: Int64) -> Int64 { (self - remainder(d)) / d }
    func remainder(_ d: Int64) -> Int64 { ((self % d) + d) % d }
}
