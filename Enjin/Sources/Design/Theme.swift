@preconcurrency import SwiftUI

/// ENJIN's look, matched to the monochrome motor icon: near-white paper, true
/// black ink, greys for state, black as the only accent. Display type is SF Pro
/// Expanded Black (precise, engine-like), reading type is SF Pro. Surfaces are
/// "stickers": a black outline and a hard offset shadow that presses down.
enum Theme {
    static let paper = Color(hex: 0xFAFAF9)
    static let card = Color(hex: 0xFFFFFF)
    static let stub = Color(hex: 0xF2F2F2)
    static let ink = Color(hex: 0x0B0B0C)
    static let inkSoft = Color(hex: 0x6A6A70)
    /// The one accent is ink itself: every "go" is black, like the icon.
    static let accent = ink
    static let accentSoft = Color(hex: 0xE9E9E9)
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
        [.init(id: "#0b0b0c", name: "Ink", color: ink), .init(id: "#e8590c", name: "Ember", color: Color(hex: 0xE8590C)),
         .init(id: "#1971c2", name: "Sky", color: sky), .init(id: "#2f9e44", name: "Leaf", color: leaf)]
    }

    static let radius: CGFloat = 12
    static let line: CGFloat = 2
    static let shadow = CGSize(width: 3, height: 4)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.expanded) }
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
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
        case .primary: Theme.accent
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
            .background(active ? Theme.accent : Theme.paper, in: .circle)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.line))
            .background(Circle().fill(Theme.ink).offset(pressed ? .zero : CGSize(width: 2, height: 3)))
            .offset(pressed ? CGSize(width: 2, height: 3) : .zero)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
            .contentShape(.circle)
    }
}

/// The ENJIN wordmark: the motor from the app icon, then the name, expanded.
struct Wordmark: View {
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.3) {
            Image("MotorMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: size * 1.25)
                .foregroundStyle(Theme.ink)
            Text(verbatim: "ENJIN")
                .font(Theme.display(size))
                .tracking(size * 0.04)
                .foregroundStyle(Theme.ink)
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
