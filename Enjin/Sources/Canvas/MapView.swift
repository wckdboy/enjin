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
                                if row.depth > 0 {
                                    Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.accent).font(.system(size: 15, weight: .bold))
                                }
                                Text(row.title)
                                    .font(row.depth == 0 ? Theme.display(26) : Theme.body(18, weight: row.id == current ? .bold : .semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(row.cardCount) cards").font(Theme.body(15)).foregroundStyle(Theme.inkSoft)
                                if row.id == current {
                                    Text("You are here").font(Theme.body(13, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.accent, in: .capsule)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .sticker(row.id == current ? Theme.accentSoft : (row.depth == 0 ? Theme.card : Theme.paper), radius: 14)
                        }
                        .buttonStyle(.plain)
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
                StickerChoice(selection: $type, options: [(.topic, "Topic", "square.stack"), (.note, "Note", "note.text")])
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
