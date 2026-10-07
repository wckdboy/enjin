import Foundation
import Testing
@testable import EnjinKit

/// The module registry: one place that teaches Enjin every medium, in step with what the canvas can render.
struct SkillTests {
    struct Shared: Decodable { var kinds: [String]; var frameKinds: [String] }

    static func shared() throws -> Shared {
        let url = ContractTests.fixtures.deletingLastPathComponent().appendingPathComponent("skills.json")
        return try JSONDecoder().decode(Shared.self, from: Data(contentsOf: url))
    }

    @Test func theCanvasAndEnjinKnowTheSameModules() throws {
        let web = try Self.shared()
        #expect(Set(web.kinds) == Set(VisualKind.allCases.map(\.rawValue)), "every kind exists on both sides")
        // Frame modules on the web = Enjin's spec modules, plus live (the agent's own HTML).
        #expect(Set(web.frameKinds) == Set(SkillRegistry.specKinds.map(\.rawValue) + ["live"]))
    }

    @Test func everyKindBelongsToExactlyOneModule() {
        for kind in VisualKind.allCases {
            #expect(SkillRegistry.all.filter { $0.kinds.contains(kind) }.count == 1, "\(kind)")
        }
    }

    @Test func enjinIsTaughtEveryModule() throws {
        for skill in SkillRegistry.all {
            #expect(Persona.system.contains(skill.pick), "persona names \(skill.id)")
            if let grammar = skill.grammar {
                let spec = AgentTools.createCards["input_schema"]?["properties"]?["cards"]?["items"]?["properties"]?["visual"]?["properties"]?["spec"]?["description"]?.stringValue
                #expect(spec?.contains(grammar) == true, "tool schema has the \(skill.id) grammar")
            }
        }
    }

    @Test func aSimNeedsBodiesAndKeepsItsSpec() {
        let empty = Visual(kind: .sim, spec: .object(["bodies": .array([])]))
        #expect(empty.sanitized() == nil)
        let ball = Visual(kind: .sim, spec: .object(["bodies": .array([.object(["id": .string("ball"), "y": .number(3)])])]))
        #expect(ball.sanitized()?.spec == ball.spec)
        // A molecule is a 3D model too, with atoms and no parts.
        let water = Visual(kind: .model3d, spec: .object(["atoms": .array([.object(["id": .string("o"), "element": .string("O")])])]))
        #expect(water.sanitized() != nil)
    }
}
