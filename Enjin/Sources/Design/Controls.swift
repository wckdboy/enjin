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

/// Lays children out in rows, wrapping when a row is full (answer chips, tags).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.items.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.items + [i], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
