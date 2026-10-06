import SwiftUI

/// Glass: frosted white Liquid Glass with a bright edge, a faint dark line
/// around it, and a soft lift off the field. Selected glass gets a black edge.
struct GlassPanel<S: InsettableShape>: ViewModifier {
    let shape: S
    var active = false

    func body(content: Content) -> some View {
        content
            // Glass must not fold its keys into one element: VoiceOver (and taps by
            // accessibility frame) need each key on its own.
            .accessibilityElement(children: .contain)
            .foregroundStyle(Theme.fg)
            .glassEffect(.regular.tint(Color.white.opacity(0.42)), in: shape)
            .overlay { shape.strokeBorder(LinearGradient(colors: [Theme.highlight, Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2) }
            .overlay { shape.inset(by: -0.5).strokeBorder(active ? Theme.fg : Theme.edge, lineWidth: active ? 1.5 : 0.75) }
            .shadow(color: .black.opacity(active ? 0.14 : 0.07), radius: active ? 22 : 26, y: active ? 8 : 14)
    }
}

/// A well (fields, tracks): sunk slightly into the glass; a black edge while focused.
struct Well<S: InsettableShape>: ViewModifier {
    let shape: S
    var focused = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.black.opacity(0.045)))
            .overlay { shape.strokeBorder(focused ? Theme.fg : Theme.edge, lineWidth: focused ? 1.5 : 0.75) }
            .animation(.snappy(duration: 0.18), value: focused)
    }
}

extension View {
    /// A glass panel.
    func panel(radius: CGFloat = Theme.radius, active: Bool = false) -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), active: active))
    }

    /// Chrome floating over the canvas.
    func chrome(radius: CGFloat) -> some View { modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: radius, style: .continuous))) }
    func chrome() -> some View { modifier(GlassPanel(shape: Capsule(style: .continuous))) }

    func well(radius: CGFloat = 14, focused: Bool = false) -> some View {
        modifier(Well(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), focused: focused))
    }
    func wellCapsule(focused: Bool = false) -> some View { modifier(Well(shape: Capsule(style: .continuous), focused: focused)) }
}

/// The field: soft white, a faint vertical light, and (optionally) the logo,
/// huge and black, sitting behind the glass so the frosting has something to bend.
struct FieldBackground: View {
    var logo = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xF7F7F5), Theme.void, Color(hex: 0xEAEAE7)], startPoint: .top, endPoint: .bottom)
            if logo {
                GeometryReader { g in
                    Logo(size: max(g.size.width, 700) * 0.5, color: Theme.fg)
                        .opacity(0.9)
                        .position(x: g.size.width * 0.88, y: g.size.width * 0.34)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Older name for the field.
typealias DotGrid = FieldBackground
