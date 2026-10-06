import Foundation
import Testing
@testable import EnjinKit

/// Runs Apple's on-device model for real when this Mac has it.
struct OnDeviceHelperTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ENJIN_LIVE"] == "1"))
    func suggestsQuestionsAndPicturePhrases() async throws {
        guard #available(macOS 26.0, *), AppleAssistHelper.isAvailable else { return }
        let h = AppleAssistHelper()
        let t0 = Date()
        let qs = await h.nextQuestions(path: ["Roman Empire", "Legions"],
                                       cards: [("Testudo", "Shields locked like a tortoise shell."), ("Who paid?", "Soldiers' wages")], lastAsk: "how did they fight?", language: .da)
        let p = await h.imagePhrase(title: "Marching camps", summary: "A fortified camp built every night.", topic: "Roman Empire")
        let en = await h.nextQuestions(path: ["Roman Empire"], cards: [("Legions", "Heavy infantry")], lastAsk: nil, language: .en)
        print("LIVE \(String(format: "%.1fs", Date().timeIntervalSince(t0))) da=\(qs) en=\(en) phrase=\(p ?? "nil")")
        #expect(qs.count >= 2)
        #expect(p != nil)
    }
}
