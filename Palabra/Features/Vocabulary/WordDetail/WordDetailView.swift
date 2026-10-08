import SwiftUI

/// Full-screen word detail: the four sections, a section jump bar, a
/// Regenerate/Delete menu, and the "Ask about this word" chat entry point.
struct WordDetailView: View {
    let word: Word
    var banner: AnyView = AnyView(EmptyView())
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showChat = false
    @State private var showRegenerate = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    banner
                    jumpBar(proxy: proxy)
                    PronunciationNotice(word: word)
                    WordContentView(content: word.content) {
                        PronunciationButton(word: word)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .background(Theme.background)
        .navigationTitle(word.spanish)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { askBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Regenerate", systemImage: "arrow.clockwise") { showRegenerate = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showChat) {
            ChatSheet(word: word)
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

    private var askBar: some View {
        Button { showChat = true } label: {
            GlassSurface(cornerRadius: Theme.Radius.pill) {
                Label("Ask about this word", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
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
