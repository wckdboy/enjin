import SwiftUI

/// A sheet in ENJIN style: paper, a hand-lettered title, sticker buttons.
struct EnjinSheet<Content: View>: View {
    let title: LocalizedStringKey
    var cancel: LocalizedStringKey? = nil
    var confirm: LocalizedStringKey? = nil
    var confirmDisabled = false
    var onConfirm: (() -> Void)? = nil
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(title: LocalizedStringKey, cancel: LocalizedStringKey?, confirm: LocalizedStringKey?, confirmDisabled: Bool = false,
         onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.cancel = cancel
        self.confirm = confirm
        self.confirmDisabled = confirmDisabled
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let cancel {
                    Button(cancel) { dismiss() }.buttonStyle(StickerButtonStyle(kind: .quiet))
                }
                Spacer()
                if let confirm, let onConfirm {
                    Button(confirm) { onConfirm(); dismiss() }
                        .buttonStyle(StickerButtonStyle(kind: .primary))
                        .disabled(confirmDisabled)
                        .opacity(confirmDisabled ? 0.5 : 1)
                        .accessibilityIdentifier("confirm")
                } else if cancel == nil {
                    Button("Done") { dismiss() }.buttonStyle(StickerButtonStyle(kind: .quiet))
                }
            }
            .overlay { Text(title).font(Theme.display(28)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            content
        }
        .background(Theme.paper.ignoresSafeArea())
        .tint(Theme.accent)
    }
}

/// A paper "field" with an ink outline, for text entry in sheets.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.body(19))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.white, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: Theme.line))
    }
}

extension View {
    func enjinField() -> some View { modifier(FieldStyle()) }

    /// Form sections on paper instead of grey.
    func enjinForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper)
            .tint(Theme.accent)
            .listRowBackground(Theme.card)
    }
}

/// Two-way choice as stickers (e.g. Topic / Note).
struct StickerChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey, String)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.0) { value, label, symbol in
                Button { selection = value } label: { Label(label, systemImage: symbol) }
                    .buttonStyle(StickerButtonStyle(kind: selection == value ? .primary : .quiet))
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}
