import EnjinKit
import SwiftUI

/// The kid's line to Enjin: ask, see what it's doing, stop, undo.
struct AgentDock: View {
    let agent: AgentSession
    let onAsk: (String) -> Void
    let onGoToSuggestion: () -> Void
    let onNextStep: (AgentSession.NextStep) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.language.languageCode?.identifier == "da" ? .da : .en }
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = agent.suggestion, let card = agent.session.card(s.cardId) {
                Button(action: onGoToSuggestion) {
                    Label { Text(verbatim: "\(s.reason) → \(card.title)") } icon: { Image(systemName: "eye") }
                        .lineLimit(1)
                }
                .buttonStyle(StickerButtonStyle(kind: .quiet, radius: 22))
                .transition(.opacity)
            }

            if !agent.nextSteps.isEmpty && !agent.isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(agent.nextSteps) { step in
                            Button { onNextStep(step) } label: {
                                switch step {
                                case .dive(_, let title):
                                    Label { Text(title) } icon: { Image(systemName: "arrow.down.right") }
                                case .ask(let q):
                                    Text(q)
                                }
                            }
                            .buttonStyle(StickerButtonStyle(kind: step.isDive ? .primary : .quiet, radius: 22))
                            .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 6)
                    .padding(.trailing, 6)
                }
                .transition(.opacity)
            }

            if let line = statusLine {
                HStack(alignment: .top, spacing: 10) {
                    if agent.isRunning && agent.prefetchingCardId == nil {
                        SparkDots()
                    } else if !isError {
                        Image(systemName: "bolt.fill").foregroundStyle(Theme.ink).font(.system(size: 15, weight: .bold))
                    }
                    Text(line)
                        .font(Theme.body(17))
                        .foregroundStyle(isError ? Color(hex: 0xC92A2A) : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                    if isError {
                        Button("OK") { agent.dismissError() }.buttonStyle(StickerButtonStyle(kind: .quiet, radius: 12))
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 10) {
                TextField(text: $text, axis: .vertical) { Text("Ask Enjin anything…") }
                    .font(Theme.body(19))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    // Multi-line fields insert a newline on Return; kids expect Return to send.
                    .onChange(of: text) { _, new in
                        if new.hasSuffix("\n") {
                            text = String(new.dropLast())
                            send()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: Theme.line))
                    .accessibilityIdentifier("askField")
                if agent.isRunning && agent.prefetchingCardId == nil {
                    Button { agent.cancel() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(IconButtonStyle(size: 48))
                        .accessibilityLabel(Text("Stop"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 20, weight: .heavy)) }
                        .buttonStyle(IconButtonStyle(active: true, size: 48))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(Text("Send"))
                        .accessibilityIdentifier("send")
                }
                if agent.canUndo && !agent.isRunning {
                    Button { Task { await agent.undoLastTurn() } } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(IconButtonStyle(size: 48))
                        .accessibilityLabel(Text("Undo Enjin's last change"))
                        .accessibilityIdentifier("undoAgent")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 640)
        .sticker(Theme.paper, radius: 24)
        .animation(.snappy, value: agent.status)
        .animation(.snappy, value: agent.suggestion)
        .animation(.snappy, value: agent.nextSteps)
    }

    private var isError: Bool {
        if case .failed = agent.status { true } else { false }
    }

    private var statusLine: String? {
        switch agent.status {
        case .failed(let message): return message
        case .working(.thinking): return agent.reply.isEmpty ? "Thinking…".localizedIn(language) : agent.reply
        case .working(.searching(let q)):
            return q.isEmpty ? "Looking things up…".localizedIn(language) : String(format: "Looking up “%@”…".localizedIn(language), q)
        case .working(.writing): return agent.reply.isEmpty ? "Making cards…".localizedIn(language) : agent.reply
        case .idle: return agent.reply.isEmpty ? nil : agent.reply
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""
        focused = false // put the keyboard away so the kid sees the cards arrive
        onAsk(t)
    }
}

extension AgentSession.NextStep {
    var isDive: Bool { if case .dive = self { true } else { false } }
}

/// Three ember dots pulsing: Enjin is working.
struct SparkDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .frame(height: 22)
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}
