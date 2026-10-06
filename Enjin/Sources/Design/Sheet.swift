import SwiftUI

/// A sheet: the field, a header with the title and its keys, then content.
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
                Text(title).font(Theme.display(24)).tracking(-0.4).foregroundStyle(Theme.fg).accessibilityAddTraits(.isHeader)
                Spacer()
                if let cancel {
                    Button(cancel) { dismiss() }.buttonStyle(KeyButtonStyle(kind: .secondary, size: .small))
                }
                if let confirm, let onConfirm {
                    Button(confirm) { onConfirm(); dismiss() }
                        .buttonStyle(KeyButtonStyle(kind: .primary, size: .small))
                        .disabled(confirmDisabled)
                        .accessibilityIdentifier("confirm")
                } else if cancel == nil {
                    Button("Done") { dismiss() }.buttonStyle(KeyButtonStyle(kind: .primary, size: .small))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            SignalLine()
            content
        }
        .background(FieldBackground().ignoresSafeArea())
        .tint(Theme.signal)
        .preferredColorScheme(.light)
    }
}

extension View {
    /// Form sections on the field, rows as dark decks.
    func enjinForm() -> some View {
        scrollContentBackground(.hidden)
            .background(FieldBackground())
            .tint(Theme.signal)
            .listRowBackground(Theme.deck)
    }
}
