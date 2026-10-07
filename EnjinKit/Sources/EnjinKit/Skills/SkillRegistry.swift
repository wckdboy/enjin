import Foundation

/// A medium Enjin can deploy on a card: what it's for (so Enjin picks it for the
/// right ideas), its grammar (so Enjin writes it right), and what it needs to be
/// drawable. The canvas renders it (canvas-web/src/live/documents.ts for frame
/// modules, src/cards/visual.ts for figures); shared/skills.json keeps the two
/// lists in step (ContractTests).
///
/// Adding a module: a runtime on the web, a Skill here, a VisualKind case. The
/// persona and the tool schema are assembled from this registry.
public struct Skill: Sendable {
    public let id: String
    public let kinds: [VisualKind]
    /// One line in the persona: when this is the right medium.
    public let pick: String
    /// The spec grammar (spec skills only), in the tool schema.
    public let grammar: String?
    /// A spec is drawable when one of these is a non-empty array.
    public let needs: [String]

    public var usesSpec: Bool { grammar != nil }
}

public enum SkillRegistry {
    public static let figure = Skill(
        id: "figure",
        kinds: [.flow, .cycle, .timeline, .bars, .parts, .stat, .formula, .code, .graph, .table, .chart],
        pick: "figure (flow, cycle, timeline, bars, chart, table, graph, parts, stat, formula, code): structure and real numbers.",
        grammar: nil, needs: [])

    public static let model3d = Skill(
        id: "model3d", kinds: [.model3d],
        pick: """
        model3d: a 3D model the explorer can turn: machines, molecules, cells, planets, anatomy, architecture. \
        Build it from primitives with real proportions, label the key parts, animate what moves.
        """,
        grammar: """
        model3d: {"parts": [{"shape": "box|sphere|cylinder|cone|torus|ring|capsule|lathe|extrude|tube", "size": [w,h,d] (box), \
        "radius", "height", "tube" (torus), "inner" (ring), "profile": [[r,y],...] (lathe: bottles, bells, rocket bodies), \
        "outline": [[x,y],...] + "depth" (extrude: gears, wings, plates), "points": [[x,y,z],...] (tube: wires, pipes, struts), \
        "position": [x,y,z], "rotation": [deg,deg,deg], "color": "white|light|grey|dark|black|accent|glass|red|blue|green|yellow", \
        "label": "short name", "detail": "one sentence shown when tapped", "group": "name", "spin": {"axis": "x|y|z", "rpm"}, \
        "orbit": {"center": [x,y,z], "rpm"}, "explode": [dx,dy,dz] (where the part flies to in exploded view)}], \
        "groups": {"name": {"pivot": [x,y,z], "spin": {...}, "orbit": {...}}} (parts of an assembly that move together), \
        "atoms": [{"id", "element": "H|C|N|O|S|P|Cl|F|Na|Fe", "position": [x,y,z], "label", "detail"}], "bonds": [[id, id, order]] \
        (molecules, ball-and-stick, ~1.5 units per bond), "camera": {"azimuth", "elevation"}, "caption"}. Y is up; real \
        proportions; up to 80 parts. Label the parts that matter and give them a detail; animate what moves; add explode \
        offsets when the inside matters. The explorer can zoom right into a labelled part to go inside it.
        """,
        needs: ["parts", "atoms"])

    public static let diorama = Skill(
        id: "diorama", kinds: [.diorama],
        pick: """
        diorama: a scene with depth: an ecosystem, a cross-section (volcano, Earth's layers, a cell), a moment \
        in history or in space, with hotspots that explain. Pair it with an illustrate prompt for a painted backdrop.
        """,
        grammar: """
        diorama: {"layers": [{"depth": 0..1 (0 far, 1 near), "items": [...]}], "hotspots": [{"x","y","label","detail"}], \
        "steps": [{"label"}] (a scrubber through stages), "caption"}. The scene is 100 wide x 60 tall, y down. Items: \
        a prop from the library {"prop": "tree|pine|mountain|hill|cloud|sun|moon|planet|stars|waves|strata|house|building|\
        factory|turbine|volcano|cell|bacterium|atom|dna|rocket|satellite|person|car|fish|bird|plant|magnet|gear", "x", "y" \
        (where it stands), "s" (scale, ~10 units tall at 1; negative flips), "fill", "accent"}, or a shape {"shape": \
        "rect|circle|ellipse|path|text", "x","y","w","h","r","rx" or "d" (SVG path), "text", "size", "fill", "stroke", "opacity"}. \
        Fills: white|light|grey|dark|black|accent|sky|water|green|earth|red|blue|glass|none or #hex. Any item, layer or hotspot \
        can have "anim": "float|pulse|spin|drift" and "step": n (or "from"/"to") to appear only in those stages. 3-5 layers \
        from far (sky) to near (ground); props do most of the drawing. Give the card an illustrate prompt to paint a backdrop.
        """,
        needs: ["layers"])

    public static let ui = Skill(
        id: "ui", kinds: [.ui],
        pick: """
        ui: generative interactive UI you design on the fly: sliders that change a formula's inputs with live \
        readouts, meters and plots ("drag the mass, watch the force"), quizzes, step-throughs, flashcards, ordering \
        games. Use it whenever the explorer can learn by changing something or testing themselves.
        """,
        grammar: """
        ui: {"state": {"name": number}, "blocks": [...]} with blocks: {"type": "heading|text|callout", "text"} (text may embed \
        {{expr}} or {{expr|digits}}), {"type": "slider", "var", "min", "max", "step", "label", "unit"}, {"type": "toggle", \
        "var", "label"}, {"type": "choice", "var", "label", "options": [{"label", "value"}]}, {"type": "play", "var", "min", \
        "max", "seconds", "label", "loop", "autoplay"} (animates a variable: time, angle), {"type": "readout", "label", "expr", \
        "unit", "digits"}, {"type": "meter", "label", "expr", "max", "unit"}, {"type": "plot", "label", "expr" (in x and \
        state), "xmin", "xmax", "ymin", "ymax", "xLabel", "marker"}, {"type": "table", "label", "columns": [...], "rows": [[text \
        or {"expr", "unit", "digits"}]]}, {"type": "quiz", "question", "options": [...], "answer": index, "explain"}, {"type": \
        "answer", "question", "answer": expr, "tolerance": 0.05, "unit", "hint", "explain"} (work it out), {"type": "match", \
        "prompt", "pairs": [[term, meaning]]}, {"type": "steps", "items": [{"title", "text"}]}, {"type": "flashcards", \
        "cards": [{"front", "back"}]}, {"type": "order", "prompt", "items": [in the correct order]}, {"type": "row", \
        "blocks": [...]}. Make the explorer's choices change real numbers, and end with a check (quiz or answer).
        """,
        needs: ["blocks"])

    public static let sim = Skill(
        id: "sim", kinds: [.sim],
        pick: """
        sim: a live 2D physics world the explorer plays with: projectiles, pendulums, springs and oscillators, \
        collisions and momentum, orbits, drag and terminal velocity, levers and ropes. Prefer it over live HTML for \
        anything mechanical: it's always physically right. They can grab and throw any body.
        """,
        grammar: """
        sim: {"view": [xmin, ymin, xmax, ymax] in metres (y up), "gravity": [gx, gy] (default [0, -9.81]), "floor": true, \
        "walls": false, "drag": c (linear air drag), "speed": 1, "params": {"name": {"value", "min", "max", "step", "label", \
        "unit"}} (up to 4 sliders), "bodies": [{"id", "shape": "circle|box", "r" or "w","h", "x", "y", "vx", "vy", "mass", \
        "fixed" (anchors, pivots, a sun), "color", "label", "trail", "bounce": 0..1}], "links": [{"type": "spring|rod|rope", \
        "a", "b", "k", "rest", "damping"}] (rest defaults to the starting distance), "forces": [{"on": "<id>|all", "fx", "fy"}], \
        "readouts": [{"label", "expr", "unit", "digits"}], "plot": [{"expr", "label", "unit"}] (up to 2, over the last 10 s), \
        "caption"}. Any number (mass too) may be a formula (a string) over the params and t; forces, readouts and plots also see every \
        body's <id>_x, <id>_y, <id>_vx, <id>_vy, and the body's own x, y, vx, vy, m. Example orbit: a fixed "sun" at the \
        origin and "fx": "-G*M*m*x/(x^2+y^2)^1.5", "fy": "-G*M*m*y/(x^2+y^2)^1.5" with G and M as params, gravity [0, 0], \
        floor false. Sliders should change what matters (length, stiffness, mass, angle, drag) with a readout of the result.
        """,
        needs: ["bodies"])

    public static let live = Skill(
        id: "live", kinds: [.live],
        pick: """
        live: your own HTML/JS simulation, when no module above can show it (algorithms stepping, fields, \
        cellular automata, signals): about one per portal, never for stubs.
        """,
        grammar: nil, needs: [])

    public static let all: [Skill] = [figure, model3d, diorama, ui, sim, live]

    public static func skill(for kind: VisualKind) -> Skill? {
        all.first { $0.kinds.contains(kind) }
    }

    /// Kinds that carry a spec and run ENJIN's own runtime.
    public static let specKinds: Set<VisualKind> = Set(all.filter(\.usesSpec).flatMap(\.kinds))

    /// For the persona: one line per medium.
    public static var catalogue: String {
        (all.map { "- \($0.pick)" } + ["- illustrate: a picture painted on the device, for what no photo can show."])
            .joined(separator: "\n")
    }

    /// For the tool schema: every spec grammar.
    public static var specGrammar: String {
        "For the modules (data, not code; ENJIN renders it):\n" + all.compactMap(\.grammar).joined(separator: "\n")
            + "\nExpressions everywhere: + - * / % ^, comparisons, a ? b : c, pi, e, g, c, and sin cos tan sqrt abs exp ln log min max pow round clamp."
    }
}
