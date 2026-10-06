import Foundation
import Testing
@testable import EnjinKit

struct PartialJSONTests {
    @Test func everyPrefixOfARealInputParsesOrIsEmpty() throws {
        let full = #"{"parentCardId": "c-1", "cards": [{"title": "Testudo \"tortoise\"", "summary": "Shields é locked.", "isStub": false, "n": -12.5}, {"title": "Pay", "isStub": true, "sources": ["https://a.b/c"]}]}"#
        var lastCards = 0
        for i in 0...full.count {
            let prefix = String(full.prefix(i))
            let v = PartialJSON.parse(prefix)
            if i > 0 { #expect(v != nil, "prefix \(i) failed: \(prefix)") }
            if case .array(let cards)? = v?["cards"] {
                #expect(cards.count >= lastCards, "cards never disappear while streaming")
                lastCards = cards.count
            }
        }
        #expect(PartialJSON.parse(full) == (try JSONDecoder().decode(JSONValue.self, from: Data(full.utf8))))
    }

    @Test func partialStringsShowTheirTextSoFar() {
        let v = PartialJSON.parse(#"{"cards": [{"title": "Roman ro"#)
        #expect(v?["cards"].flatMap { if case .array(let a) = $0 { a.first } else { nil } }?["title"] == .string("Roman ro"))
    }

    @Test func halfKeysAndLiteralsAreDropped() {
        #expect(PartialJSON.parse(#"{"cards": [{"title": "A", "isSt"#) == .object(["cards": .array([.object(["title": .string("A")])])]))
        #expect(PartialJSON.parse(#"{"a": tr"#) == .object([:]))
        #expect(PartialJSON.parse(#"{"a": "x\"#) == .object(["a": .string("x")]))
    }
}
