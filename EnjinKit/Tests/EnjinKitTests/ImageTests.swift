import Foundation
import Testing
@testable import EnjinKit

struct WikimediaTests {
    static func page(_ index: Int, _ title: String, file: String, w: Int = 800, h: Int = 533) -> JSONValue {
        .object(["index": .number(Double(index)), "title": .string(title), "pageimage": .string(file),
                 "thumbnail": .object(["source": .string("https://upload.example/\(file).jpg"), "width": .number(Double(w)), "height": .number(Double(h))])])
    }

    static func finder(pages: [JSONValue], categories: [String: String] = [:]) -> WikimediaImages {
        WikimediaImages(fetch: { url in
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if q.contains(where: { $0.name == "generator" }) {
                return try JSONEncoder().encode(JSONValue.object(["query": .object(["pages": .array(pages)])]))
            }
            if let t = q.first(where: { $0.name == "titles" })?.value {
                let file = String(t.dropFirst("File:".count))
                let meta: JSONValue = .object([
                    "Artist": .object(["value": .string("<a href='x'>Jane Doe</a>")]),
                    "LicenseShortName": .object(["value": .string("CC BY-SA 4.0")]),
                    "ImageDescription": .object(["value": .string("A picture")]),
                    "Categories": .object(["value": .string(categories[file] ?? "History")]),
                ])
                return try JSONEncoder().encode(JSONValue.object(["query": .object(["pages": .array([.object(["imageinfo": .array([
                    .object(["extmetadata": meta, "descriptionurl": .string("https://commons.example/File:\(file)")]),
                ])])])])]))
            }
            return Data("JPEGBYTES-\(url.lastPathComponent)".utf8)
        })
    }

    @Test func picksTheFirstSafeLargeEnoughUnusedPicture() async throws {
        let f = Self.finder(pages: [
            Self.page(3, "Legion", file: "good.jpg"),
            Self.page(1, "Nude statue", file: "statue.jpg"),
            Self.page(2, "Icon", file: "tiny.png", w: 100, h: 90),
            Self.page(0, "Battle", file: "battle.jpg"),
        ], categories: ["battle.jpg": "Corpses in art"])
        let found = try #require(try await f.find("roman legion", excluding: []))
        #expect(found.sourceURL == "https://commons.example/File:good.jpg")
        #expect(found.credit == "Jane Doe · CC BY-SA 4.0")
        #expect(found.mimeType == "image/jpeg")
        #expect(String(decoding: found.data, as: UTF8.self) == "JPEGBYTES-good.jpg.jpg")

        let none = try await f.find("roman legion", excluding: ["https://commons.example/File:good.jpg"])
        #expect(none == nil, "already-used pictures are skipped")
    }
}

/// Returns a fixed picture per query, honouring exclusions.
struct FakeFinder: ImageFinder {
    var answers: [String: [String]] // query -> source URLs in preference order
    func find(_ query: String, excluding: Set<String>) async throws -> FoundImage? {
        guard let url = answers[query]?.first(where: { !excluding.contains($0) }) else { return nil }
        return FoundImage(data: Data("PNG".utf8), mimeType: "image/png", width: 640, height: 480, credit: "Someone · CC0", sourceURL: url)
    }
}

@MainActor
struct StreamingAndImageTests {
    func make(_ steps: [ScriptedBackend.Step], finder: ImageFinder?) async throws -> (AgentSession, FakeCanvas) {
        let store = NotebookStore(root: tempRoot())
        let nb = try demoData()
        try await store.save(nb)
        let session = try await NotebookSession.open(nb.meta.id, store: store)
        _ = try await session.scene(for: "p-root")
        let agent = AgentSession(session: session, backend: ScriptedBackend(steps), telemetry: nil)
        agent.imageFinder = finder
        let canvas = FakeCanvas()
        agent.canvas = canvas
        return (agent, canvas)
    }

    func settle(_ agent: AgentSession) async throws {
        for _ in 0..<500 where agent.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(50)) // background picture lookups
    }

    @Test func streamedCardsAppearEarlyAndKeepTheirIds() async throws {
        let final: JSONValue = .object(["cards": .array([
            .object(["title": .string("Testudo"), "summary": .string("Shields locked together."), "isStub": .bool(false)]),
            .object(["title": .string("Who paid?"), "summary": .string("Soldiers' wages."), "isStub": .bool(true)]),
        ])])
        let raw = String(decoding: try JSONEncoder().encode(final), as: UTF8.self)
        let partials = stride(from: 20, through: raw.count, by: 15).map { String(raw.prefix($0)) }
        let (agent, canvas) = try await make([
            .init(events: partials.map { .toolInputProgress(id: "toolu_x", name: "createCards", partial: $0) },
                  calls: [("createCards", final)]),
        ], finder: nil)
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        try await settle(agent)

        let made = agent.session.activeCards(in: "p-root").filter { $0.createdByTurnId != nil }
        #expect(made.map(\.title) == ["Testudo", "Who paid?"])
        // The first canvas op is a streamed preview of a card that's still being written...
        let firstUpsert = canvas.ops.flatMap(\.1).first.flatMap { if case .upsert(let c) = $0 { c } else { nil } }
        #expect(firstUpsert?.state == .filling)
        // ...with the same id as the final card, so nothing jumps; and nothing was deleted.
        #expect(firstUpsert?.id == made.first?.id)
        #expect(!canvas.ops.flatMap(\.1).contains { if case .delete = $0 { true } else { false } })
    }

    @Test func picturesArriveAfterTheCardAndAreRemembered() async throws {
        let (agent, canvas) = try await make([
            .init(calls: [createCards([
                .object(["title": .string("Legion"), "summary": .string("x"), "isStub": .bool(false), "image": .string("legion")]),
                .object(["title": .string("Another legion"), "summary": .string("y"), "isStub": .bool(false), "image": .string("legion")]),
                .object(["title": .string("No pic"), "summary": .string("z"), "isStub": .bool(false), "image": .string("nothing")]),
            ])]),
        ], finder: FakeFinder(answers: ["legion": ["https://c/1", "https://c/2"]]))
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        try await settle(agent)

        let cards = agent.session.activeCards(in: "p-root").filter { $0.createdByTurnId != nil }
        let a = try #require(cards.first { $0.title == "Legion" })
        let b = try #require(cards.first { $0.title == "Another legion" })
        let c = try #require(cards.first { $0.title == "No pic" })
        #expect(a.image != nil && b.image != nil)
        #expect(a.image?.sourceURL != b.image?.sourceURL, "two cards don't get the same picture")
        #expect(c.image == nil && c.imageQuery == nil, "no picture: placeholder goes away")
        #expect(canvas.files.count == 2)
        #expect(a.image?.credit == "Someone · CC0")
        // Persisted, and served with the portal's scene.
        let reloaded = try await agent.session.store.load(agent.session.id)
        #expect(reloaded.cards.first { $0.id == a.id }?.image == a.image)
        #expect(try await agent.session.scene(for: "p-root")?.files?.count == 2)
    }

    @Test func picturesOffMeansNoPlaceholders() async throws {
        let (agent, canvas) = try await make([
            .init(calls: [createCards([.object(["title": .string("Legion"), "summary": .string("x"), "isStub": .bool(false), "image": .string("legion")])])]),
        ], finder: nil)
        agent.ask("go", portalId: "p-root", focusCardId: nil)
        try await settle(agent)
        let upserts = canvas.ops.flatMap(\.1).compactMap { if case .upsert(let c) = $0 { c } else { nil } }
        #expect(upserts.allSatisfy { $0.imagePending == nil })
    }
}

/// Hits the real Wikipedia API. Opt-in: ENJIN_LIVE=1 swift test --filter LiveWikimedia
struct LiveWikimediaTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ENJIN_LIVE"] == "1"))
    func findsRealPictures() async throws {
        let finder = WikimediaImages()
        for q in ["Roman legionary", "Colosseum", "Via Appia", "testudo formation"] {
            let found = try await finder.find(q, excluding: [])
            print("LIVE \(q): \(found.map { "\($0.width)x\($0.height) \($0.mimeType) \($0.data.count)B \($0.credit ?? "-") \($0.sourceURL)" } ?? "nil")")
            #expect(found != nil, "no picture for \(q)")
            if let f = found { #expect(f.data.count > 5_000) }
        }
    }
}
