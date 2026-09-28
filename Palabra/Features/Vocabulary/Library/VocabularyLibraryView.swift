import SwiftUI
import SwiftData

/// The app's main screen. Reads words live via `@Query`; every write goes
/// through `environment.repository`.
struct VocabularyLibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]

    @State private var searchText = ""
    @State private var inputText = ""
    @State private var activeFlow: AddWordFlow?
    @State private var duplicateCandidate: Word?
    @State private var pendingDelete: Word?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                if filteredWords.isEmpty {
                    emptyContent.padding(.top, Theme.Spacing.xl)
                } else if environment.libraryLayout == .grid {
                    HoneycombGrid(words: filteredWords, onSelect: open, onDeleteRequest: { pendingDelete = $0 })
                        .padding(.top, Theme.Spacing.md)
                } else {
                    WordListView(words: filteredWords, onSelect: open, onDeleteRequest: { pendingDelete = $0 })
                        .padding(.top, Theme.Spacing.md)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .searchable(text: $searchText, prompt: "Search your words")
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(Motion.standard) {
                        environment.libraryLayout = environment.libraryLayout == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: environment.libraryLayout == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(environment.libraryLayout == .grid ? "Switch to readability layout" : "Switch to grid layout")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { environment.router.openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $activeFlow) { flow in
            WordPreviewSheet(flow: flow) { saved in
                environment.router.openWord(saved.id)
            }
        }
        .confirmationDialog(
            "\"\(duplicateCandidate?.spanish ?? "")\" is already in your Library",
            isPresented: Binding(get: { duplicateCandidate != nil }, set: { if !$0 { duplicateCandidate = nil } }),
            presenting: duplicateCandidate
        ) { existing in
            Button("Open Existing") { environment.router.openWord(existing.id) }
            Button("Regenerate") {
                activeFlow = AddWordFlow(inputWord: existing.spanish, mode: .regenerate(existingID: existing.id, existingCreatedAt: existing.createdAt), environment: environment)
                inputText = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.spanish ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { word in
            Button("Delete", role: .destructive) { environment.repository.delete(id: word.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filteredWords: [Word] {
        let query = WordKey.search(searchText)
        guard !query.isEmpty else { return words }
        return words.filter { $0.searchKey.contains(query) }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if words.isEmpty {
            EmptyStateView(systemImage: "text.book.closed", title: "Your library is empty", message: "Add the first Spanish word you'd like to learn.")
        } else {
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "No saved words match \"\(searchText)\".")
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            if !environment.hasAPIKey {
                MissingAPIKeyPrompt(onOpenSettings: { environment.router.openSettings() })
            } else if environment.selectedModel == nil {
                MissingModelPrompt(onOpenSettings: { environment.router.openSettings() })
            } else {
                AddWordBar(text: $inputText, isEnabled: activeFlow == nil, onSubmit: submit)
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func open(_ word: Word) {
        environment.router.openWord(word.id)
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60, activeFlow == nil else { return }
        let key = WordKey.identity(trimmed)
        if let existing = environment.repository.find(key: key) {
            duplicateCandidate = existing
            return
        }
        activeFlow = AddWordFlow(inputWord: trimmed, mode: .new, environment: environment)
        inputText = ""
    }
}
