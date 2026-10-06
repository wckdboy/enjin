import CoreText
@preconcurrency import SwiftUI

/// ENJIN's look: warm paper, deep ink, one ember accent, chunky Lilita One for
/// display (also used for card titles on the canvas), rounded system text for
/// reading, and "sticker" surfaces with an ink outline and a hard offset shadow
/// that presses down when tapped.
enum Theme {
    static let paper = Color(hex: 0xFFFAF0)
    static let card = Color(hex: 0xFFF4E6)
    static let stub = Color(hex: 0xF1F3F5)
    static let ink = Color(hex: 0x2A2A3C)
    static let inkSoft = Color(hex: 0x5C5F73)
    static let ember = Color(hex: 0xE8590C)
    static let emberSoft = Color(hex: 0xFFE8D9)
    static let sky = Color(hex: 0x1971C2)
    static let leaf = Color(hex: 0x2F9E44)

    /// Drawing colors on the tool rail (also used by Pencil ink).
    struct InkColor: Identifiable, Equatable {
        let id: String // hex, as Excalidraw wants it
        let name: LocalizedStringKey
        let color: Color
        static func == (a: InkColor, b: InkColor) -> Bool { a.id == b.id }
    }
    static var inkColors: [InkColor] {
        [.init(id: "#2a2a3c", name: "Ink", color: ink), .init(id: "#e8590c", name: "Ember", color: ember),
         .init(id: "#1971c2", name: "Sky", color: sky), .init(id: "#2f9e44", name: "Leaf", color: leaf)]
    }

    static let radius: CGFloat = 16
    static let line: CGFloat = 2
    static let shadow = CGSize(width: 3, height: 4)

    static func display(_ size: CGFloat) -> Font { .custom("LilitaOne", size: size) }
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }

    /// Lilita One ships inside the app, unmodified (OFL 1.1, see Fonts/OFL-LilitaOne.txt).
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "LilitaOne-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Paper surface, ink outline, hard offset shadow.
struct Sticker: ViewModifier {
    var fill: Color = Theme.paper
    var radius: CGFloat = Theme.radius
    var lifted = true

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.ink, lineWidth: Theme.line))
            .background(
                RoundedRectangle(cornerRadius: radius).fill(Theme.ink)
                    .offset(lifted ? Theme.shadow : .zero)
            )
    }
}

extension View {
    func sticker(_ fill: Color = Theme.paper, radius: CGFloat = Theme.radius, lifted: Bool = true) -> some View {
        modifier(Sticker(fill: fill, radius: radius, lifted: lifted))
    }
}

/// Buttons that feel like pressing a sticker into the page.
struct StickerButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, quiet }
    var kind: Kind = .plain
    var radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill: Color = switch kind {
        case .primary: Theme.ember
        case .plain: Theme.paper
        case .quiet: Theme.card
        }
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.ink, lineWidth: Theme.line))
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.ink).offset(pressed ? .zero : Theme.shadow))
            .offset(pressed ? Theme.shadow : .zero)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
            .contentShape(.rect)
    }
}

/// Round icon sticker (toolbar actions).
struct IconButtonStyle: ButtonStyle {
    var active = false
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? Color.white : Theme.ink)
            .frame(width: size, height: size)
            .background(active ? Theme.ember : Theme.paper, in: .circle)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.line))
            .background(Circle().fill(Theme.ink).offset(pressed ? .zero : CGSize(width: 2, height: 3)))
            .offset(pressed ? CGSize(width: 2, height: 3) : .zero)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
            .contentShape(.circle)
    }
}

/// The ENJIN wordmark: hand-drawn letters and an ember spark.
struct Wordmark: View {
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.06) {
            Text(verbatim: "ENJIN")
                .font(Theme.display(size))
                .foregroundStyle(Theme.ink)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.ember)
                .offset(y: size * 0.05)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Enjin"))
    }
}

/// Section headings in the hand-drawn face.
struct HandHeading: View {
    let text: LocalizedStringKey
    var size: CGFloat = 28

    var body: some View {
        Text(text).font(Theme.display(size)).foregroundStyle(Theme.ink)
    }
}
