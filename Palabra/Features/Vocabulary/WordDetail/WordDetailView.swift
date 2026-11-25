import SwiftUI
import UIKit

/// Full-screen word detail: the four sections, a section jump bar, a
/// Regenerate/Delete menu, and the "Ask about this word" chat entry point.
struct WordDetailView: View {
    let word: Word
    var banner: AnyView = AnyView(EmptyView())
    var onAsk: ((UUID, String) -> Void)?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var showRegenerate = false
    @State private var showDeleteConfirm = false
    @State private var shareImage: Image?
    @State private var swipes = 0
    var tints = WordTintSettings()

    var body: some View {
        // Decoded once per render (it is JSON behind a computed property), then used by the page and the share text.
        let content = word.content
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    banner
                    jumpBar(proxy: proxy)
                    PronunciationNotice(word: word)
                    WordContentView(content: content) {
                        PronunciationButton(word: word)
                    }
                    // Below the jump bar (a horizontal scroller of its own), so swiping chips never turns the page.
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded(handleSwipe))
                }
                .padding(Theme.Spacing.md)
            }
        }
        .background { ScreenBackdrop() }
        .sensoryFeedback(.selection, trigger: swipes)
        // Drawn once per version of the word, so the share sheet never waits on it.
        .task(id: word.updatedAt) {
            shareImage = WordShareCard.render(content: word.content, tint: tints.color(key: word.key, partOfSpeech: word.partOfSpeech))
        }
        .navigationTitle(word.spanish)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { askBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: WordShareText.make(content)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview(word.spanish, image: shareImage)) {
                            Label("Share as Image", systemImage: "photo")
                        }
                    }
                    Button("Regenerate", systemImage: "arrow.clockwise") { showRegenerate = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showRegenerate) {
            WordPreviewSheet(
                flow: AddWordFlow(inputWord: word.spanish, mode: .regenerate(existingID: word.id, existingCreatedAt: word.createdAt), environment: environment),
                onSaved: { _ in }
            )
        }
        .confirmationDialog("Delete \"\(word.spanish)\"?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: requestDelete)
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A clear sideways swipe moves to the next or previous word in the order the library showed.
    private func handleSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        guard abs(dx) > 90, abs(dx) > abs(dy) * 2,
              value.startLocation.x > 12, value.startLocation.x < UIScreen.main.bounds.width - 44 else { return }
        let order = environment.router.wordOrder
        guard let index = order.firstIndex(of: word.id) else { return }
        // Swiping toward the leading edge goes forward, so right-to-left languages flip.
        let forward = (dx < 0) == (layoutDirection == .leftToRight)
        let target = forward ? index + 1 : index - 1
        guard order.indices.contains(target) else { return }
        swipes += 1
        Motion.animate(Motion.standard) { environment.router.openWord(order[target]) }
    }

    private func jumpBar(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(WordSection.allCases) { section in
                    Button {
                        Motion.animate(Motion.standard) { proxy.scrollTo(section, anchor: .top) }
                    } label: {
                        Chip(titleKey: section.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var askBar: some View {
        if let onAsk {
            askButton { onAsk(word.id, word.spanish) }
        }
    }

    private func askButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Ask about this word", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassAccessory()
    }

    /// Dismiss first, delete 0.6s later — so nothing on screen reads a
    /// deleted SwiftData model mid-transition (plan note N5).
    private func requestDelete() {
        dismiss()
        let id = word.id
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            environment.repository.delete(id: id)
        }
    }
}
