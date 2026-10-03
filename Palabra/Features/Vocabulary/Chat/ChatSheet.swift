import SwiftUI

struct ChatSheet: View {
    let word: Word
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: ChatViewModel?
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ChatBody(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(word.spanish)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Conversation", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) { viewModel?.clear() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = ChatViewModel(word: word, environment: environment) }
        }
    }
}

private struct ChatBody: View {
    @Bindable var viewModel: ChatViewModel
    private let suggestions = ["Explain more simply", "Give me another example", "Formal or informal?", "Use it in a conversation"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if viewModel.messages.isEmpty {
                            suggestionChips
                        }
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message) {
                                Task { await viewModel.retryLastFailed() }
                            }
                            .id(message.id)
                        }
                        if viewModel.sendState == .sending {
                            TypingIndicator()
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        Motion.animate(Motion.quick) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background(Theme.background)
    }

    private var suggestionChips: some View {
        FlowLayout {
            ForEach(suggestions, id: \.self) { suggestion in
                Button { Task { await viewModel.send(suggestion) } } label: {
                    Chip(text: suggestion)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Ask about this word…", text: $viewModel.draft)
                .textFieldStyle(.plain)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sendState == .sending)
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: () -> Void

    var body: some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if message.status == .failed {
                    Text(LocalizedStringKey(message.errorText ?? "Something went wrong. Try again."))
                        .foregroundStyle(Theme.error)
                    Button("Retry", action: onRetry)
                        .font(.caption.weight(.semibold))
                } else {
                    Text(message.text)
                        .foregroundStyle(message.role == .user ? .white : Theme.ink)
                }
            }
            .padding(Theme.Spacing.md)
            .background {
                if message.status == .failed {
                    Theme.error.opacity(0.1)
                } else if message.role == .user {
                    Theme.accent
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            if message.role == .user { Spacer(minLength: 40) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct TypingIndicator: View {
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
