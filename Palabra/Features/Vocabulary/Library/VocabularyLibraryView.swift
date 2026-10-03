import SwiftUI
import SwiftData

/// The app's main screen. Reads words live via `@Query`; every write goes
/// through `environment.repository`.
struct VocabularyLibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Query(sort: \WordQueueItem.createdAt, order: .forward) private var queuedItems: [WordQueueItem]

    @State private var searchText = ""
    @State private var inputText = ""
    @State private var activeFlow: AddWordFlow?
    @State private var duplicateCandidate: Word?
    @State private var pendingDelete: Word?
    @State private var selectedTag: String?
    @State private var showOrganizeSheet = false
    @State private var showOrganizeSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                if !queuedItems.isEmpty {
                    QueuedWordsBanner(
                        items: queuedItems,
                        onRetry: { id in
                            environment.wordQueue.markPending(id: id, attempts: 0, lastError: nil)
                            environment.queueProcessor.drain(environment: environment)
                        },
                        onRemove: { id in environment.wordQueue.remove(id: id) }
                    )
                }
                if !words.isEmpty {
                    TagFilterBar(tags: LibrarySections.tagCounts(words), selected: $selectedTag)
                        .padding(.top, Theme.Spacing.sm)
                }
                if filteredWords.isEmpty {
                    emptyContent.padding(.top, Theme.Spacing.xl)
                } else if showSections {
                    SectionedLibraryView(
                        sections: LibrarySections.group(filteredWords, order: environment.organizerSettings.sectionOrder, unorganizedTitle: "Not organized yet"),
                        layout: environment.libraryLayout,
                        showTags: environment.organizerSettings.showTagsInList,
                        onSelect: open,
                        onDeleteRequest: { pendingDelete = $0 }
                    )
                    .padding(.top, Theme.Spacing.md)
                } else if environment.libraryLayout == .grid {
                    HoneycombGrid(words: filteredWords, onSelect: open, onDeleteRequest: { pendingDelete = $0 })
                        .padding(.top, Theme.Spacing.md)
                } else {
                    WordListView(words: filteredWords, showTags: environment.organizerSettings.showTagsInList, onSelect: open, onDeleteRequest: { pendingDelete = $0 })
                        .padding(.top, Theme.Spacing.md)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .searchable(text: $searchText, prompt: "Search words or #tags")
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Motion.animate(Motion.standard) {
                        environment.libraryLayout = environment.libraryLayout == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: environment.libraryLayout == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(environment.libraryLayout == .grid ? "Switch to readability layout" : "Switch to grid layout")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showOrganizeSheet = true
                    } label: {
                        Label("Re-organize Library", systemImage: "sparkles.rectangle.stack")
                    }
                    .disabled(words.isEmpty)
                    Button {
                        showOrganizeSettings = true
                    } label: {
                        Label("Organization Settings", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
                .accessibilityIdentifier("moreOptionsMenu")
            }
        }
        .sheet(isPresented: $showOrganizeSheet) {
            OrganizeLibrarySheet(wordCount: words.count, unorganizedCount: words.filter { $0.category == nil }.count)
        }
        .sheet(isPresented: $showOrganizeSettings) {
            NavigationStack { OrganizationSettingsView() }
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

    /// Sections only make sense once at least one word has been organized.
    private var showSections: Bool {
        environment.organizerSettings.groupIntoSections && words.contains { $0.category != nil }
    }

    private var filteredWords: [Word] {
        words.filter { word in
            LibrarySections.matches(word, query: searchText)
                && (selectedTag.map { tag in word.tags.contains(tag) } ?? true)
        }
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
