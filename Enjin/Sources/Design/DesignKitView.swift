#if DEBUG
import SwiftUI

/// Every piece of the ENJIN kit on one screen. Open with `-designKit` (debug builds).
struct DesignKitView: View {
    @State private var level = "student"
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .center) {
                    Wordmark(size: 44)
                    Spacer()
                }
                SectionHeader(title: "Type") { Readout("Inter · SF Mono") }
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "Display 56").font(Theme.display(56)).tracking(-1.2).foregroundStyle(Theme.fg)
                    Text(verbatim: "Title 26").font(Theme.title(26)).foregroundStyle(Theme.fg)
                    Text(verbatim: "Body 17. How a motor turns electricity into motion.").font(Theme.body(17)).foregroundStyle(Theme.fg)
                    Text(verbatim: "Secondary 15. The rotor chases the field.").font(Theme.body(15)).foregroundStyle(Theme.fgSoft)
                    Readout(text: Text(verbatim: "Readout · 12 cards · step 3/6"))
                }

                SectionHeader(title: "Surfaces") { Readout("glass · selected · well") }
                HStack(spacing: 20) {
                    swatch("Glass").panel()
                    swatch("Selected").panel(active: true)
                    swatch("Well").well(radius: 18)
                }

                SectionHeader(title: "Keys")
                HStack(spacing: 14) {
                    Button {} label: { Label("Explore", systemImage: "arrow.right") }.buttonStyle(KeyButtonStyle(kind: .primary, size: .large))
                    Button("Dive in") {}.buttonStyle(KeyButtonStyle(kind: .primary))
                    Button("Visualize") {}.buttonStyle(KeyButtonStyle(kind: .secondary))
                    Button("Robots") {}.buttonStyle(KeyButtonStyle(kind: .secondary, size: .small))
                    Button("Quiet") {}.buttonStyle(KeyButtonStyle(kind: .quiet))
                    Button("Off") {}.buttonStyle(KeyButtonStyle(kind: .primary)).disabled(true)
                    Button {} label: { Image(systemName: "map") }.buttonStyle(RotorKeyStyle())
                    Button {} label: { Image(systemName: "arrow.up") }.buttonStyle(RotorKeyStyle(active: true))
                }

                SectionHeader(title: "Controls")
                VStack(alignment: .leading, spacing: 20) {
                    GearSelector(selection: $level, options: [("curious", "Curious", "sparkles"), ("student", "Student", "graduationcap"), ("expert", "Expert", "atom")])
                    TextField(text: $text) { Text(verbatim: "A field in a well…") }.focused($focused).enjinField(focused: focused)
                    HStack(spacing: 28) {
                        SignalMeter(progress: 0.62)
                        Activity(size: 28, working: true)
                        Activity(size: 28)
                    }
                    SignalLine(lit: true)
                }

                SectionHeader(title: "Chrome") { Readout("over the canvas") }
                HStack(alignment: .top, spacing: 24) {
                    HStack(spacing: 8) {
                        Button {} label: { Image(systemName: "chevron.left") }.buttonStyle(RotorKeyStyle(active: true, size: 38))
                        Text(verbatim: "Electric motors").font(Theme.title(20)).foregroundStyle(Theme.fg).padding(.trailing, 12)
                    }
                    .padding(6)
                    .chrome()
                    VStack(spacing: 4) {
                        ForEach(["cursorarrow", "pencil.tip", "highlighter", "textformat"], id: \.self) { s in
                            Button {} label: { Image(systemName: s) }.buttonStyle(ToolKeyStyle(active: s == "pencil.tip"))
                        }
                    }
                    .padding(6)
                    .chrome()
                }
            }
            .padding(40)
        }
        .background(FieldBackground().ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func swatch(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text(verbatim: name).font(Theme.title(20)).foregroundStyle(Theme.fg)
            Readout(text: Text(verbatim: "surface"))
        }
        .padding(18)
        .frame(width: 180, height: 140, alignment: .leading)
    }
}
#endif
