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
        VStack(spacing: 0) {
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
            }
            inputBar
        }
        .background(Theme.background)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Motion.animate(Motion.quick) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var intro: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            Text("Ask me anything, or have me change your library, decks and review list.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            FlowLayout {
                ForEach(starters, id: \.self) { starter in
                    Button { Task { await session.send(starter) } } label: {
                        Chip(titleKey: LocalizedStringKey(starter))
                    }
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("Message…", text: $session.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($focused)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .accessibilityIdentifier("chatField")
            Button {
                Task { await session.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.accent : Theme.inkSecondary.opacity(0.4))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }
}

private struct ChatTurnView: View {
    let turn: ChatTurn
    let session: ChatSession
    let isLast: Bool

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(verbatim: turn.text)
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.md)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }
        case .assistant:
            assistant
        }
    }

    @ViewBuilder
    private var assistant: some View {
        if turn.status == .failed {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(LocalizedStringKey(turn.errorText ?? "Something went wrong. Try again."))
                    .foregroundStyle(Theme.error)
                if isLast {
                    Button("Retry") { Task { await session.retry() } }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("chatRetryButton")
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.error.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !turn.text.isEmpty {
                    Text(ChatMarkdown.attributed(turn.text))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(turn.actions) { action in
                    ChatActionRow(action: action)
                }
                if isLast && turn.actions.contains(where: { $0.state == .pending }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Apply") { Task { await session.approvePending() } }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("applyActionsButton")
                        Button("Not now") { Task { await session.declinePending() } }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("declineActionsButton")
                    }
                    .disabled(session.isBusy)
                }
            }
        }
    }
}

private struct ChatActionRow: View {
    let action: ChatAction

    var body: some View {
        if action.isWrite {
            GlassSurface(cornerRadius: Theme.Radius.medium) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(action.state == .failed ? Theme.error : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: action.summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        status
                            .font(.caption)
                            .foregroundStyle(action.state == .failed ? Theme.error : Theme.inkSecondary)
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
                ChatActionText.readTitle(action.capability)
            }
            .font(.caption)
            .foregroundStyle(action.state == .failed ? Theme.error : Theme.inkSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chatReadChip")
        }
    }

    private var icon: String {
        switch action.state {
        case .pending: return "circle.dashed"
        case .applied: return "checkmark.circle.fill"
        case .declined: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
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
        .padding(Theme.Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear { animate = true }
    }
}
