@preconcurrency import SwiftUI

/// ENJIN design language: white, black and glass. A soft light field, frosted
/// white Liquid Glass surfaces with a bright edge, black type, and black for the
/// one thing to press or what's selected. No colour in the chrome; colour belongs
/// to content (drawing inks, pictures). The logo (the three-quarter motor from the
/// app icon) is the only mark, and it sits large behind the glass.
///
/// The pieces:
/// - Surfaces.swift: glass panels and chrome, wells, the field.
/// - Keys.swift: primary (solid black), glass, and round icon keys, with haptics.
/// - Controls.swift: gear selector, fields.
/// - Marks.swift: logo, wordmark, logo spinner, readouts, headings, lines.
/// - DesignKitView.swift: every component on one screen (debug builds, `-designKit`).
enum Theme {
    /// The field everything floats in: soft white.
    static let void = Color(hex: 0xF2F2F0)
    /// Solid faces (canvas cards, wells' surroundings).
    static let deck = Color.white
    static let deckHigh = Color(hex: 0xF7F7F6)
    /// Type and lines.
    static let fg = Color(hex: 0x0B0B0C)
    static let fgSoft = Color(hex: 0x66666B)
    static let fgFaint = Color(hex: 0xA6A6AB)
    /// Edges: a bright highlight on glass, a faint dark line around it.
    static let edge = Color.black.opacity(0.08)
    static let edgeStrong = Color.black.opacity(0.18)
    static let highlight = Color.white.opacity(0.85)
    /// Selection, focus, the thing to press: black.
    static let signal = Color(hex: 0x0B0B0C)
    static let ember = Color(hex: 0xE8590C)
    static let sky = Color(hex: 0x1971C2)
    static let leaf = Color(hex: 0x2F9E44)
    static let danger = Color(hex: 0xD63B3B)

    // Names the screens use.
    static var ink: Color { fg }
    static var inkSoft: Color { fgSoft }
    static var paper: Color { void }
    static var card: Color { deck }
    static var stub: Color { deckHigh }
    static var accent: Color { signal }
    static var accentSoft: Color { deckHigh }
    static var hairline: Color { edge }

    /// Drawing colors on the tool rail (also used by Pencil ink).
    struct InkColor: Identifiable, Equatable {
        let id: String // hex, as Excalidraw wants it
        let name: LocalizedStringKey
        let color: Color
        static func == (a: InkColor, b: InkColor) -> Bool { a.id == b.id }
    }
    static var inkColors: [InkColor] {
        [.init(id: "#0b0b0c", name: "Ink", color: fg), .init(id: "#e8590c", name: "Ember", color: ember),
         .init(id: "#1971c2", name: "Sky", color: sky), .init(id: "#2f9e44", name: "Leaf", color: leaf)]
    }

    static let radius: CGFloat = 22
    static let line: CGFloat = 1

    // MARK: Type (Inter, registered at launch; SF Mono for readouts)

    static func display(_ size: CGFloat) -> Font { .custom("InterDisplay-Bold", fixedSize: size) }
    static func title(_ size: CGFloat) -> Font { .custom("InterDisplay-Bold", fixedSize: size) }
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        let face = switch weight {
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold, .heavy, .black: "Inter-Bold"
        default: "Inter-Regular"
        }
        return .custom(face, fixedSize: size)
    }
    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
