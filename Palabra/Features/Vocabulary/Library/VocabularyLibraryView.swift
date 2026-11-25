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
    @State private var savedCount = 0
    @AppStorage("librarySort") private var sortRaw = LibrarySort.newest.rawValue
    @AppStorage("libraryKind") private var kindRaw = LibraryKind.all.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PinnedWords.key) private var pinnedRaw = ""
    @State private var duplicateCandidate: Word?
    /// Deleted words stay hidden (and restorable) for a few seconds before they are removed for good.
    @State private var hiddenIDs: Set<UUID> = []
    @State private var undoTarget: UndoTarget?
    @State private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    @State private var spellPrompt: SpellPrompt?
    @State private var mastery: [UUID: Double] = [:]
    @State private var selectedTag: String?
    @State private var showOrganizeSheet = false
    @State private var showOrganizeSettings = false
    @State private var lastRandomID: UUID?
    @State private var randomCount = 0

    var body: some View {
        ZStack {
            ScreenBackdrop()
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
                    Picker("Show", selection: $kindRaw) {
                        ForEach(LibraryKind.allCases) { option in
                            Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                    .accessibilityIdentifier("libraryKindPicker")
                    TagFilterBar(tags: LibrarySections.tagCounts(words.filter(kind.includes)), selected: $selectedTag)
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
                        onDeleteRequest: softDelete
                    )
                    .padding(.top, Theme.Spacing.md)
                } else if environment.libraryLayout == .grid {
                    HoneycombGrid(words: filteredWords, onSelect: open, onDeleteRequest: softDelete)
                        .padding(.top, Theme.Spacing.md)
                } else {
                    WordListView(words: filteredWords, showTags: environment.organizerSettings.showTagsInList, onSelect: open, onDeleteRequest: softDelete)
                        .padding(.top, Theme.Spacing.md)
                }
            }
            .environment(\.wordMastery, mastery)
            .environment(\.pinnedWordIDs, pinnedIDs)
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search words or #tags")
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
                Button(action: openRandom) {
                    Image(systemName: "shuffle")
                }
                .disabled(filteredWords.isEmpty)
                .accessibilityLabel("Random Word")
                .accessibilityIdentifier("randomWordButton")
                Menu {
                    Picker("Sort", selection: $sortRaw) {
                        ForEach(LibrarySort.allCases) { option in
                            Label(LocalizedStringKey(option.title), systemImage: option.systemImage).tag(option.rawValue)
                        }
                    }
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
        // A tag from the other tab would leave this one empty with no visible reason.
        .onChange(of: kindRaw) { _, _ in selectedTag = nil }
        .sensoryFeedback(.success, trigger: savedCount)
        .sensoryFeedback(.selection, trigger: randomCount)
        .sensoryFeedback(.impact(weight: .light), trigger: undoTarget?.id)
        .task { mastery = environment.wordMastery() }
        .onChange(of: words.count) { _, _ in mastery = environment.wordMastery() }
        // Reviewing happens on the Study tab: coming back shows the new progress.
        .onChange(of: environment.router.tab) { _, tab in
            if tab == .spanish { mastery = environment.wordMastery() }
        }
        // Leaving the screen or the app makes pending deletes final: nothing is left half-done.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commitPendingDeletes() }
        }
        .onDisappear { commitPendingDeletes() }
        .sheet(item: $activeFlow) { flow in
            WordPreviewSheet(flow: flow) { saved in
                savedCount += 1
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
            "Did you mean \"\(spellPrompt?.suggestion ?? "")\"?",
            isPresented: Binding(get: { spellPrompt != nil }, set: { if !$0 { spellPrompt = nil } }),
            presenting: spellPrompt
        ) { prompt in
            Button("Use \"\(prompt.suggestion)\"") { proceed(with: prompt.suggestion) }
            Button("Keep \"\(prompt.original)\"") { startFlow(prompt.original) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The spelling looks off. Checking now saves a request.")
        }
    }

    private struct SpellPrompt {
        let original: String
        let suggestion: String
    }

    private struct UndoTarget: Equatable {
        let id: UUID
        let title: String
    }

    private var pinnedIDs: Set<UUID> { PinnedWords.decode(pinnedRaw) }

    /// Sections only make sense once at least one word has been organized.
    private var showSections: Bool {
        environment.organizerSettings.groupIntoSections && words.contains { $0.category != nil }
    }

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .newest }

    private var kind: LibraryKind { LibraryKind(rawValue: kindRaw) ?? .all }

    private var filteredWords: [Word] {
        let shown = sort.apply(words.filter { word in
            !hiddenIDs.contains(word.id)
                && kind.includes(word)
                && LibrarySections.matches(word, query: searchText)
                && (selectedTag.map { tag in word.tags.contains(tag) } ?? true)
        })
        return PinnedWords.floated(shown, pinned: pinnedIDs, id: \.id)
    }

    @ViewBuilder
    private var emptyContent: some View {
        if words.isEmpty {
            EmptyStateView(systemImage: "text.book.closed", title: "Your library is empty", message: "Add the first Spanish word you'd like to learn.")
        } else if searchText.isEmpty, selectedTag == nil, kind == .words {
            EmptyStateView(systemImage: "textformat.abc", title: "No words yet", message: "Entries of more than one word are under Phrases.")
        } else if searchText.isEmpty, selectedTag == nil, kind == .phrases {
            EmptyStateView(systemImage: "text.bubble", title: "No phrases yet", message: "Add a phrase or a sentence, like \"cómo estás\", and it will show up here.")
        } else {
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "No saved words match \"\(searchText)\".")
        }
    }

    /// The word being typed, when it is already saved: shown as a chip above the bar instead of after submitting.
    private var typedDuplicate: Word? {
        let key = WordKey.identity(inputText)
        guard !key.isEmpty, activeFlow == nil else { return nil }
        return words.first { $0.key == key && !hiddenIDs.contains($0.id) }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let undoTarget {
                UndoToast(title: undoTarget.title, onUndo: undo)
            }
            if let existing = typedDuplicate {
                Button { open(existing) } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                        Text("Already in your Library").foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        Text("Open").foregroundStyle(Theme.accentDeep).fontWeight(.bold)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .glassCapsule()
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("duplicateChip")
            }
            Group {
                if !environment.hasAPIKey {
                    MissingAPIKeyPrompt(onOpenSettings: { environment.router.openSettings() })
                } else if environment.selectedModel == nil {
                    MissingModelPrompt(onOpenSettings: { environment.router.openSettings() })
                } else {
                    AddWordBar(text: $inputText, isEnabled: activeFlow == nil, onSubmit: submit)
                }
            }
        }
        .animation(Motion.reduced(Motion.quick), value: undoTarget)
        .animation(Motion.reduced(Motion.quick), value: typedDuplicate?.id)
    }

    private func open(_ word: Word) {
        // The word screen swipes between neighbours in the order the library shows right now.
        environment.router.wordOrder = filteredWords.map(\.id)
        environment.router.openWord(word.id)
    }

    /// Opens a random word from what the library is showing now (respects the filter, search and tag).
    private func openRandom() {
        guard let id = RandomWord.pick(from: filteredWords.map(\.id), excluding: lastRandomID) else { return }
        lastRandomID = id
        randomCount += 1
        environment.router.wordOrder = filteredWords.map(\.id)
        environment.router.openWord(id)
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60, activeFlow == nil else { return }
        let key = WordKey.identity(trimmed)
        if let existing = environment.repository.find(key: key) {
            duplicateCandidate = existing
            return
        }
        // A typo would cost a request: ask first. (UI tests skip this so their stub words are never questioned.)
        if !ProcessInfo.processInfo.arguments.contains("-UITestStub"),
           let suggestion = SpellSuggestion.suggestion(for: trimmed) {
            spellPrompt = SpellPrompt(original: trimmed, suggestion: suggestion)
            return
        }
        startFlow(trimmed)
    }

    /// The person accepted a correction: it may already be saved.
    private func proceed(with word: String) {
        if let existing = environment.repository.find(key: WordKey.identity(word)) {
            inputText = ""
            duplicateCandidate = existing
            return
        }
        startFlow(word)
    }

    private func startFlow(_ word: String) {
        guard activeFlow == nil else { return }
        activeFlow = AddWordFlow(inputWord: word, mode: .new, environment: environment)
        inputText = ""
    }

    // MARK: Delete with undo

    private func softDelete(_ word: Word) {
        let id = word.id
        Motion.animate(Motion.quick) {
            hiddenIDs.insert(id)
            undoTarget = UndoTarget(id: id, title: word.spanish)
        }
        let env = environment
        deleteTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            env.repository.delete(id: id)
            finishDelete(id)
        }
    }

    private func undo() {
        guard let target = undoTarget else { return }
        deleteTasks[target.id]?.cancel()
        deleteTasks[target.id] = nil
        Motion.animate(Motion.quick) {
            hiddenIDs.remove(target.id)
            undoTarget = nil
        }
    }

    private func finishDelete(_ id: UUID) {
        deleteTasks[id] = nil
        hiddenIDs.remove(id)
        if undoTarget?.id == id { undoTarget = nil }
    }

    /// Removes every hidden word for good right now (the screen is closing, or the app left the foreground).
    private func commitPendingDeletes() {
        for id in hiddenIDs {
            deleteTasks[id]?.cancel()
            environment.repository.delete(id: id)
            finishDelete(id)
        }
    }
}
