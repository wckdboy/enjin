import SwiftUI

/// The logo: the three-quarter motor from the app icon. The only mark ENJIN uses.
struct Logo: View {
    var size: CGFloat = 40
    var color: Color = Theme.fg

    var body: some View {
        Image("MotorHero").renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The wordmark: the logo, then ENJIN.
struct Wordmark: View {
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.32) {
            Logo(size: size * 1.2)
            Text(verbatim: "ENJIN")
                .font(Theme.display(size))
                .tracking(size * 0.08)
                .foregroundStyle(Theme.fg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Enjin"))
    }
}

/// The logo as Enjin's activity light: still when idle, turning while it works.
struct Rotor: View {
    var size: CGFloat = 22
    var spinning = false
    var color: Color? = nil
    @State private var angle = 0.0

    var body: some View {
        Logo(size: size, color: color ?? Theme.fg)
            .rotationEffect(.degrees(angle))
            .task(id: spinning) {
                guard spinning else { return }
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 1.2)) { angle += 360 }
                    try? await Task.sleep(for: .seconds(1.2))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Bigger logo, for heroes and empty states.
typealias MotorArt = Logo

/// HUD readout: SF Mono capitals, tracked out. For counts, status, labels.
struct Readout: View {
    let text: Text
    var color: Color = Theme.fgSoft

    init(_ key: LocalizedStringKey, color: Color = Theme.fgSoft) { text = Text(key); self.color = color }
    init(text: Text, color: Color = Theme.fgSoft) { self.text = text; self.color = color }

    var body: some View {
        text.font(Theme.mono(11.5)).tracking(1.6).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Headings: Inter Display Bold, tracked tight.
struct Heading: View {
    let text: LocalizedStringKey
    var size: CGFloat = 28

    var body: some View {
        Text(text).font(Theme.display(size)).tracking(-size * 0.02).foregroundStyle(Theme.fg)
    }
}

/// A section title: the logo small, the title, a readout on the right.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var size: CGFloat = 26
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Logo(size: size * 0.95)
            Heading(text: title, size: size)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, size: CGFloat = 26) { self.init(title: title, size: size) { EmptyView() } }
}

/// A fine line that fades out at both ends: the HUD's divider.
struct SignalLine: View {
    var lit = false

    var body: some View {
        LinearGradient(colors: [.clear, lit ? Theme.fg : Theme.edgeStrong, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A segmented level meter (spending, progress).
struct SignalMeter: View {
    var progress: Double
    var count = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                let on = Double(i) < progress * Double(count) - 0.001
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(on ? Theme.fg : Theme.fgFaint.opacity(0.45))
                    .frame(width: 6, height: 18)
            }
        }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) %"))
    }
}
