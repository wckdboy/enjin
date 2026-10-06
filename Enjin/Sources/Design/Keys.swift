import SwiftUI

/// Keys. Primary is solid black with white type (the one thing to press);
/// secondary is glass; quiet is just type. A light rigid tap on press.
struct KeyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    enum Size { case small, regular, large }
    var kind: Kind = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, kind: kind, size: size)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed
            let (h, font, pad): (CGFloat, Font, CGFloat) = switch size {
            case .small: (34, Theme.body(15, weight: .semibold), 14)
            case .regular: (44, Theme.body(17, weight: .semibold), 18)
            case .large: (56, Theme.body(19, weight: .bold), 26)
            }
            configuration.label
                .font(font)
                .lineLimit(1)
                .padding(.horizontal, pad)
                .frame(minHeight: h)
                .foregroundStyle(kind == .primary ? Color.white : Theme.fg)
                .background {
                    switch kind {
                    case .primary:
                        Capsule().fill(Theme.fg).shadow(color: .black.opacity(enabled ? 0.18 : 0), radius: 10, y: 5)
                    case .secondary:
                        Capsule().fill(.clear).glassEffect(.regular.tint(Color.white.opacity(0.5)).interactive(), in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.75))
                    case .quiet:
                        Capsule().fill(Color.black.opacity(pressed ? 0.06 : 0))
                    }
                }
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(pressed ? 0.96 : 1)
                .contentShape(.capsule)
                .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
                .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: pressed) { _, now in now }
        }
    }
}

/// Round icon keys: glass; active is solid black.
struct RotorKeyStyle: ButtonStyle {
    var active = false
    var size: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        RoundBody(configuration: configuration, active: active, size: size)
    }

    private struct RoundBody: View {
        let configuration: Configuration
        let active: Bool
        let size: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(active ? Color.white : Theme.fg)
                .frame(width: size, height: size)
                .background {
                    if active {
                        Circle().fill(Theme.fg).shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    } else {
                        Circle().fill(.clear).glassEffect(.regular.tint(Color.white.opacity(0.5)).interactive(), in: .circle)
                            .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 0.75))
                    }
                }
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(pressed ? 0.92 : 1)
                .contentShape(.circle)
                .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
                .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: pressed) { _, now in now }
        }
    }
}

/// A tool on the rail: bare until chosen, then a black disc with a white glyph.
struct ToolKeyStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(active ? Color.white : Theme.fg.opacity(0.85))
            .frame(width: 44, height: 44)
            .background {
                Circle().fill(active ? Theme.fg : Color.black.opacity(configuration.isPressed ? 0.06 : 0))
            }
            .shadow(color: active ? .black.opacity(0.18) : .clear, radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(.circle)
            .animation(.spring(duration: 0.16, bounce: 0.3), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: active)
    }
}

// Older names used around the app.
typealias MachineButtonStyle = KeyButtonStyle
typealias IconButtonStyle = RotorKeyStyle
typealias RailButtonStyle = ToolKeyStyle
