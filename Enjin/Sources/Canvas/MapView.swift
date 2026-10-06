import EnjinKit
import SwiftUI

/// "See the whole map": every portal in the notebook, fully expanded.
struct MapView: View {
    let session: NotebookSession
    let current: String?
    let onSelect: (String) -> Void

    struct Row: Identifiable {
        let id: String
        let title: String
        let cardCount: Int
        let depth: Int
    }

    /// Depth-first, always fully expanded: the point is to see everything at once.
    private func rows(_ portal: Portal, depth: Int = 0) -> [Row] {
        let cards = session.activeCards(in: portal.portalId)
        // Children follow the order of the cards that own them.
        let children = cards.compactMap { card in session.data.portals.first { $0.ownerCardId == card.id } }
        return [Row(id: portal.portalId, title: portal.title, cardCount: cards.count, depth: depth)]
            + children.flatMap { rows($0, depth: depth + 1) }
    }

    var body: some View {
        EnjinSheet(title: "Map") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.portal(session.rootPortalId).map { rows($0) } ?? []) { row in
                        Button { onSelect(row.id) } label: {
                            HStack(spacing: 12) {
                                if row.depth > 0 { Readout(text: Text(verbatim: String(repeating: "›", count: min(row.depth, 4))), color: Theme.fgFaint) }
                                Text(row.title)
                                    .foregroundStyle(Theme.fg)
                                    .font(row.depth == 0 ? Theme.display(26) : Theme.body(18, weight: row.id == current ? .bold : .semibold))
                                Spacer()
                                Readout(text: Text("\(row.cardCount) cards"))
                                if row.id == current { Readout("You are here", color: Theme.signal) }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, row.depth == 0 ? 16 : 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(MapRowStyle(current: row.id == current, root: row.depth == 0))
                        .padding(.leading, CGFloat(row.depth) * 28)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(row.title))
                        .accessibilityValue(Text("\(row.cardCount) cards"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("map:\(row.title)")
                    }
                }
                .padding(24)
            }
        }
    }
}

/// A map row is a glass key: the portal you're in has a lit edge.
private struct MapRowStyle: ButtonStyle {
    let current: Bool
    let root: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .panel(radius: 16, active: current || configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.16, bounce: 0.3), value: configuration.isPressed)
    }
}

struct NewCardSheet: View {
    @State private var type: CardType = .topic
    @State private var title = ""
    @State private var summary = ""
    let onCreate: (CardType, String, String) -> Void

    var body: some View {
        EnjinSheet(title: "New card", cancel: "Cancel", confirm: "Add",
                   confirmDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty) {
            onCreate(type, title.trimmingCharacters(in: .whitespaces), summary.trimmingCharacters(in: .whitespaces))
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                SegmentChoice(selection: $type, options: [(.topic, "Topic", "square.stack"), (.note, "Note", "note.text")])
                TextField(text: $title) { Text("Title") }.enjinField().accessibilityIdentifier("cardTitle")
                TextField(text: $summary, axis: .vertical) { Text("What's it about?") }.lineLimit(2...5).enjinField()
                Text(type == .topic ? "Topics can be dived into and explored." : "Notes are for your own thoughts.")
                    .font(Theme.body(15)).foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
