import SwiftUI

/// A gear selector: a well with one black segment that slides to your pick
/// (Depth: Curious / Student / Expert).
struct GearSelector<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey, String)]
    @Namespace private var gear

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label, symbol in
                let on = selection == value
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { selection = value }
                } label: {
                    Label(label, systemImage: symbol)
                        .font(Theme.body(15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .foregroundStyle(on ? Color.white : Theme.fgSoft)
                        .background {
                            if on {
                                Capsule().fill(Theme.fg)
                                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "gear", in: gear)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .wellCapsule()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

typealias SegmentChoice = GearSelector

extension View {
    /// A text field in a well; its edge turns black while you type.
    func enjinField(focused: Bool = false) -> some View {
        self
            .font(Theme.body(18))
            .foregroundStyle(Theme.fg)
            .tint(Theme.signal)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .well(radius: 14, focused: focused)
    }
}
