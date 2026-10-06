@preconcurrency import SwiftUI

/// ENJIN's look, taken from the mark (a motor seen end-on): near-white paper, true
/// black ink, greys for state, black as the only accent. Shapes are the mark's:
/// circles, capsules, concentric rings. Display type is SF Pro Expanded Black,
/// reading type is SF Pro, and small machine "readouts" (counts, status) are
/// SF Mono in capitals. Content sits on machined white panels with hairline
/// edges; chrome that floats over the canvas is Liquid Glass.
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
    /// The machined edge on panels and fields.
    static let hairline = Color(hex: 0x0B0B0C).opacity(0.14)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.expanded) }
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A machined panel: white, a hairline edge, a soft contact shadow.
struct Panel: ViewModifier {
    var fill: Color = Theme.card
    var radius: CGFloat = Theme.radius
    var lifted = true

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(lifted ? 0.06 : 0), radius: 1, y: 1)
            .shadow(color: Theme.ink.opacity(lifted ? 0.07 : 0), radius: 14, y: 8)
    }
}

/// Liquid Glass for chrome that floats over the canvas.
struct Chrome<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
    }
}

extension View {
    func panel(_ fill: Color = Theme.card, radius: CGFloat = Theme.radius, lifted: Bool = true) -> some View {
        modifier(Panel(fill: fill, radius: radius, lifted: lifted))
    }

    func chrome(radius: CGFloat) -> some View { modifier(Chrome(shape: .rect(cornerRadius: radius))) }
    func chrome() -> some View { modifier(Chrome(shape: .capsule)) }
}

/// Capsule buttons. Primary is solid ink (the one "go"), plain is glass,
/// quiet is a white chip with a hairline (for use on panels and inside glass).
struct MachineButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, quiet }
    var kind: Kind = .plain
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : Theme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background {
                switch kind {
                case .primary: Capsule().fill(Theme.ink)
                case .quiet: Capsule().fill(Theme.card).strokeBorder(Theme.hairline, lineWidth: 1)
                case .plain: Capsule().fill(.clear)
                }
            }
            .glassEffect(kind == .plain ? .regular.interactive() : .identity, in: .capsule)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.35), value: pressed)
            .contentShape(.capsule)
    }
}

/// Round glass icon button; active is solid ink.
struct IconButtonStyle: ButtonStyle {
    var active = false
    var size: CGFloat = 44
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(active ? Color.white : Theme.ink)
            .frame(width: size, height: size)
            .glassEffect(active ? .regular.tint(Theme.ink).interactive() : .regular.interactive(), in: .circle)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.35), value: pressed)
            .contentShape(.circle)
    }
}

/// The ENJIN wordmark: the mark from the app icon, then the name, expanded.
struct Wordmark: View {
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.32) {
            Rotor(size: size * 1.05)
            Text(verbatim: "ENJIN")
                .font(Theme.display(size))
                .tracking(size * 0.06)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Enjin"))
    }
}

/// The mark itself. When `spinning`, the rotor turns: Enjin is working.
struct Rotor: View {
    var size: CGFloat = 22
    var spinning = false
    var color: Color = Theme.ink

    var body: some View {
        Image("MotorMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .modifier(Spin(on: spinning))
            .accessibilityHidden(true)
    }
}

/// Steps the rotor one coil (60 degrees) at a time, like a stepper motor.
private struct Spin: ViewModifier {
    let on: Bool
    @State private var steps = 0.0
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(steps * 60))
            .task(id: on) {
                guard on else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(420))
                    withAnimation(.spring(duration: 0.32, bounce: 0.25)) { steps += 1 }
                }
            }
    }
}

/// Section headings: expanded black.
struct Heading: View {
    let text: LocalizedStringKey
    var size: CGFloat = 28

    var body: some View {
        Text(text).font(Theme.display(size)).foregroundStyle(Theme.ink)
    }
}

/// A machine readout: SF Mono, capitals, tracked out. For counts and status.
struct Readout: View {
    let text: Text
    var color: Color = Theme.inkSoft

    init(_ key: LocalizedStringKey, color: Color = Theme.inkSoft) { text = Text(key); self.color = color }
    init(text: Text, color: Color = Theme.inkSoft) { self.text = text; self.color = color }

    var body: some View {
        text.font(Theme.mono(12)).tracking(1.2).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Engineering paper: a faint dot grid.
struct DotGrid: View {
    var spacing: CGFloat = 24

    var body: some View {
        Canvas { ctx, size in
            let dot = Path(ellipseIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8))
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    ctx.fill(dot.offsetBy(dx: x, dy: y), with: .color(Theme.ink.opacity(0.10)))
                    x += spacing
                }
                y += spacing
            }
        }
        .background(Theme.paper)
        .accessibilityHidden(true)
    }
}
