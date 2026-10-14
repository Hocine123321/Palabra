import SwiftUI

/// One conversation: messages, the assistant's actions with Apply / Not now, and the input bar.
struct ChatView: View {
    let conversationID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var session: ChatSession?
    @State private var didLoad = false
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if let session {
                ChatContent(session: session)
            } else if didLoad {
                EmptyStateView(systemImage: "questionmark.circle", title: "Chat not found", message: "This chat may have been deleted.")
            } else {
                ProgressView()
            }
        }
        .background(ScreenBackdrop())
        .navigationTitle(session.map { Text(verbatim: $0.title) } ?? Text("Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Conversation", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { session?.clear() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if session == nil { session = environment.makeChatSession(conversationID: conversationID) }
            didLoad = true
        }
    }
}

private struct ChatContent: View {
    @Bindable var session: ChatSession
    @FocusState private var focused: Bool

    private var starters: [String] {
        session.isLinkedToWord
            ? ["Explain it more simply", "Give me another example", "Is it formal or informal?", "Make flashcards for it"]
            : ["Add some words to my library", "What should I review?", "Make a flashcard deck for me", "Teach me a new word"]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if session.turns.isEmpty { intro }
                    ForEach(session.turns) { turn in
                        ChatTurnView(turn: turn, session: session, isLast: turn.id == session.turns.last?.id)
                    }
                    if session.phase == .thinking { ChatTypingIndicator() }
                    if session.phase == .running {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("Working…").font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.turns.count) { scrollToBottom(proxy) }
            .onChange(of: session.phase) { scrollToBottom(proxy) }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Motion.animate(Motion.quick) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var intro: some View {
        VStack(spacing: Theme.Spacing.md) {
            IconTile(systemImage: "sparkles", tint: Theme.accent, size: 64)
            Text("Ask me anything, or have me change your library, decks and review list.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            FlowLayout {
                ForEach(starters, id: \.self) { starter in
                    Button { Task { await session.send(starter) } } label: {
                        Text(LocalizedStringKey(starter))
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.glassAction)
                    .accessibilityIdentifier("chatStarter")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var canSend: Bool {
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isBusy
    }

    /// A floating glass capsule over the conversation. The field and the send button
    /// sit on flat fills inside it, never on more glass.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("Message…", text: $session.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($focused)
                .padding(.vertical, Theme.Spacing.sm)
                .accessibilityIdentifier("chatField")
            Button {
                Task { await session.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? Theme.onTint : Theme.inkSecondary)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Theme.accent : Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xs + 2)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .glassCapsule()
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

private struct ChatTurnView: View {
    let turn: ChatTurn
    let session: ChatSession
    let isLast: Bool

    /// Bubble corners: the corner nearest the speaker is tight. Leading/trailing, so it mirrors in RTL.
    private func bubbleShape(tightLeading: Bool) -> UnevenRoundedRectangle {
        let tight: CGFloat = 6
        let round = Theme.Radius.medium
        return UnevenRoundedRectangle(
            topLeadingRadius: round,
            bottomLeadingRadius: tightLeading ? tight : round,
            bottomTrailingRadius: tightLeading ? round : tight,
            topTrailingRadius: round,
            style: .continuous
        )
    }

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(verbatim: turn.text)
                    .foregroundStyle(Theme.onTint)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 4)
                    .background(Theme.accent, in: bubbleShape(tightLeading: false))
            }
        case .assistant:
            assistant
        }
    }

    @ViewBuilder
    private var assistant: some View {
        if turn.status == .failed {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(LocalizedStringKey(turn.errorText ?? "Something went wrong. Try again."))
                    .foregroundStyle(Theme.error)
                if isLast {
                    Button("Retry") { Task { await session.retry() } }
                        .buttonStyle(.glassAction)
                        .accessibilityIdentifier("chatRetryButton")
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.error.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !turn.text.isEmpty {
                    HStack(spacing: 0) {
                        Text(ChatMarkdown.attributed(turn.text))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm + 4)
                            .background(Theme.surface, in: bubbleShape(tightLeading: true))
                            .overlay {
                                bubbleShape(tightLeading: true)
                                    .stroke(Theme.ink.opacity(0.06), lineWidth: 1)
                            }
                        Spacer(minLength: 24)
                    }
                }
                ForEach(turn.actions) { action in
                    ChatActionRow(action: action)
                }
                if isLast && turn.actions.contains(where: { $0.state == .pending }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { Task { await session.approvePending() } } label: {
                            Text("Apply")
                        }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("applyActionsButton")
                        Button { Task { await session.declinePending() } } label: {
                            Text("Not now")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xs)
                        }
                        .buttonStyle(.glassAction)
                        .accessibilityIdentifier("declineActionsButton")
                    }
                    .disabled(session.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChatActionRow: View {
    let action: ChatAction

    var body: some View {
        if action.isWrite {
            GlassSurface(cornerRadius: Theme.Radius.card) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    IconTile(systemImage: icon, tint: iconTint, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: action.summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        status
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusColor)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.md)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chatActionCard")
        } else {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: action.state == .failed ? "exclamationmark.triangle" : "eye")
                    .accessibilityHidden(true)
                ChatActionText.readTitle(action.capability)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(action.state == .failed ? Theme.error : Theme.inkSecondary)
            .padding(.horizontal, Theme.Spacing.sm + 4)
            .padding(.vertical, 6)
            .background(Theme.fill.opacity(0.8), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chatReadChip")
        }
    }

    private var icon: String {
        switch action.state {
        case .pending: return "circle.dashed"
        case .applied: return "checkmark"
        case .declined: return "xmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// Orange while it waits for the person; muted tints once it is settled.
    private var iconTint: Color {
        switch action.state {
        case .pending: return Theme.tileTints[0]
        case .applied: return Theme.tileTints[1]
        case .declined: return Theme.tileTints[5]
        case .failed: return Theme.tileTints[4]
        }
    }

    private var statusColor: Color {
        switch action.state {
        case .pending: return Theme.accentDeep
        case .applied, .declined: return Theme.inkSecondary
        case .failed: return Theme.error
        }
    }

    @ViewBuilder
    private var status: some View {
        switch action.state {
        case .pending: Text("Waiting for your OK")
        case .applied: Text("Done")
        case .declined: Text("Not applied")
        case .failed: Text(verbatim: action.result ?? "")
        }
    }
}

/// Friendly titles for the quiet "I looked something up" chips.
enum ChatActionText {
    @ViewBuilder
    static func readTitle(_ capability: String) -> some View {
        switch capability {
        case "library.words": Text("Looked through your library")
        case "library.word": Text("Opened a word")
        case "stats.wordsPerDay", "stats.wordsPerWeek": Text("Checked your progress")
        case "review.list": Text("Checked your review list")
        case "study.decks": Text("Checked your decks")
        default: Text("Looked something up")
        }
    }
}

enum ChatMarkdown {
    /// Inline Markdown only, and never tappable links (the text comes from the AI).
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let linked = result.runs.compactMap { $0.link != nil ? $0.range : nil }
        for range in linked { result[range].link = nil }
        return result
    }
}

private struct ChatTypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.inkSecondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0.5)
                    .animation(Motion.reduced(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15)), value: animate)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 4)
        .background(Theme.surface, in: Capsule())
        .accessibilityHidden(true)
        .onAppear { animate = true }
    }
}
