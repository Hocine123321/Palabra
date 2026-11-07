import SwiftUI

/// The reading screen: pages you swipe through, with Focus Mode, Magnifying Glass and a table of contents.
struct BookReaderView: View {
    let bookID: String
    /// A page id (`lesson/page`) to open on; nil resumes where the person stopped.
    let startPageID: String?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var index = 0
    @State private var focus = false
    @State private var showContents = false
    @State private var started = false
    @State private var context = ReaderContext()
    @State private var isEditing = false
    @State private var editSheet: EditSheet?
    @State private var confirmDeletePage = false
    @State private var editFailed = false

    var body: some View {
        if let book = environment.books.book(id: bookID), !book.isEmpty {
            reader(book)
        } else {
            EmptyStateView(
                systemImage: "book.closed",
                title: "No lessons yet",
                message: "Lessons are added to the app in updates."
            )
            .frame(maxHeight: .infinity)
            .background { ScreenBackdrop(style: .calm) }
        }
    }

    private func reader(_ book: Book) -> some View {
        let palette = Theme.Textbook.palette(for: book.subject)
        let direction: LayoutDirection = book.isRightToLeft ? .rightToLeft : .leftToRight
        let safeIndex = min(max(index, 0), book.pages.count - 1)
        return ZStack(alignment: .bottom) {
            palette.paper.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(book.pages.indices, id: \.self) { i in
                    BookPageView(page: book.pages[i], editing: isEditing ? pageEditing(book.pages[i]) : nil).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: Theme.Spacing.sm) {
                if let term = context.activeTerm {
                    TermCard(term: term) { context.activeTerm = nil }
                        .transition(.opacity)
                }
                if context.recall.isEnabled {
                    RecallBar(pageID: book.pages[safeIndex].id)
                        .transition(.opacity)
                }
                ReaderControlBar(book: book, index: $index, focus: $focus, showContents: $showContents)
            }
            .animation(Motion.reduced(Motion.quick), value: context.activeTerm)
            .animation(Motion.reduced(Motion.quick), value: context.recall.isEnabled)
        }
        .environment(\.layoutDirection, direction)
        .environment(\.bookPalette, palette)
        .environment(context)
        .dynamicTypeSize(readerTypeSize)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(focus ? .hidden : .visible, for: .navigationBar)
        .toolbar(focus ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(focus)
        .persistentSystemOverlays(focus ? .hidden : .automatic)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if environment.books.lessonStore != nil {
                    Button {
                        Motion.animate { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "square.and.pencil")
                    }
                    .accessibilityLabel(isEditing ? "Done Editing" : "Edit")
                    .accessibilityIdentifier("editToggle")
                }
                Button {
                    context.recall.setEnabled(!context.recall.isEnabled)
                } label: {
                    Image(systemName: context.recall.isEnabled ? "magnifyingglass.circle.fill" : "magnifyingglass")
                }
                .accessibilityLabel("Magnifying Glass")
                .accessibilityIdentifier("recallToggle")
                Menu {
                    Picker("Text Size", selection: textSizeBinding) {
                        ForEach(ReaderTextSize.allCases) { size in
                            Text(size.titleKey).tag(size)
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Text Size")
                .accessibilityIdentifier("textSizeMenu")
            }
        }
        .sheet(isPresented: $showContents) {
            BookContentsView(book: book, currentIndex: safeIndex) { target in
                Motion.animate { index = target }
            }
            .environment(\.layoutDirection, direction)
            .environment(\.bookPalette, palette)
        }
        .sheet(item: $editSheet) { sheet in
            editorSheet(sheet, book: book)
                .environment(\.layoutDirection, direction)
        }
        .confirmationDialog("Delete this page?", isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) {
                let page = book.pages[safeIndex]
                apply(page) { LessonEditor.deletePage($0, pageID: page.page.id) }
            }
        }
        .alert("The change couldn't be saved.", isPresented: $editFailed) { Button("OK", role: .cancel) {} }
        .onAppear { start(book) }
        .onChange(of: index) { _, newValue in
            context.activeTerm = nil
            guard book.pages.indices.contains(newValue) else { return }
            environment.books.recordVisit(bookID: book.id, pageID: book.pages[newValue].id)
        }
        .onChange(of: context.recall.level) { _, level in
            environment.books.preferences.recallLevel = level
        }
    }

    // MARK: Editing

    /// Runs an edit on the page's lesson, saves it, and keeps the reader on the same page (or the nearest one when it is gone).
    @discardableResult
    private func apply(_ page: BookPage, _ change: (Lesson) -> Lesson) -> Bool {
        guard environment.books.editLesson(id: page.lessonID, change) else {
            editFailed = true
            return false
        }
        guard let book = environment.books.book(id: bookID) else { return true }
        if let same = book.index(ofPage: page.id) {
            index = same
        } else {
            index = min(max(index, 0), max(book.pages.count - 1, 0))
        }
        return true
    }

    private func pageEditing(_ page: BookPage) -> PageEditing {
        let pageID = page.page.id
        let blocks = page.page.blocks
        return PageEditing(
            editDetails: { editSheet = .details(pageID: pageID) },
            editBlock: { i in
                guard blocks.indices.contains(i), let draft = BlockDraft(blocks[i]) else { return }
                editSheet = .block(pageID: pageID, index: i, draft: draft)
            },
            insertBlock: { i in editSheet = .newBlock(pageID: pageID, at: i) },
            moveBlock: { from, to in apply(page) { LessonEditor.moveBlock($0, pageID: pageID, from: from, to: to) } },
            deleteBlock: { i in apply(page) { LessonEditor.deleteBlock($0, pageID: pageID, index: i) } },
            addPage: {
                var newID = ""
                let title = String(localized: "New page")
                let saved = apply(page) {
                    let result = LessonEditor.addPage($0, after: pageID, title: title)
                    newID = result.pageID
                    return result.lesson
                }
                if saved, let book = environment.books.book(id: bookID),
                   let target = book.index(ofPage: "\(page.lessonID)/\(newID)") {
                    index = target
                }
            },
            movePage: { offset in
                apply(page) { LessonEditor.movePage($0, pageID: pageID, by: offset) }
                // The page moved: follow it.
                if let book = environment.books.book(id: bookID), let target = book.index(ofPage: page.id) { index = target }
            },
            deletePage: { confirmDeletePage = true }
        )
    }

    @ViewBuilder
    private func editorSheet(_ sheet: EditSheet, book: Book) -> some View {
        switch sheet {
        case .block(let pageID, let at, let draft):
            BlockEditorView(draft: draft, isNew: false) { block in
                if let page = lessonPage(book, pageID) {
                    apply(page) { LessonEditor.replaceBlock($0, pageID: pageID, index: at, with: block) }
                }
            }
        case .newBlock(let pageID, let at):
            BlockEditorView(draft: BlockDraft(kind: .paragraph), isNew: true) { block in
                if let page = lessonPage(book, pageID) {
                    apply(page) { LessonEditor.insertBlock($0, pageID: pageID, at: at, block: block) }
                }
            }
        case .details(let pageID):
            if let page = lessonPage(book, pageID) {
                PageDetailsEditorView(
                    lessonTitle: page.lessonTitle,
                    pageTitle: page.page.title,
                    dateLabel: page.page.dateLabel ?? ""
                ) { lessonTitle, pageTitle, dateLabel in
                    apply(page) { lesson in
                        var result = LessonEditor.renameLesson(lesson, title: lessonTitle)
                        result = LessonEditor.setPageTitle(result, pageID: pageID, title: pageTitle)
                        return LessonEditor.setDateLabel(result, pageID: pageID, label: dateLabel)
                    }
                }
            }
        }
    }

    /// The laid-out page of the lesson the reader is on, by its page id inside the lesson.
    private func lessonPage(_ book: Book, _ pageID: String) -> BookPage? {
        let current = book.pages[min(max(index, 0), book.pages.count - 1)]
        return book.pages.first { $0.lessonID == current.lessonID && $0.page.id == pageID }
    }

    private func start(_ book: Book) {
        guard !started else { return }
        started = true
        context.recall.setLevel(environment.books.preferences.recallLevel)
        let target = startPageID.flatMap { book.index(ofPage: $0) }
            ?? book.resumeIndex(lastPageID: environment.books.lastPageID(bookID: book.id))
        index = target
        environment.books.recordVisit(bookID: book.id, pageID: book.pages[target].id)
    }

    private var textSizeBinding: Binding<ReaderTextSize> {
        Binding(
            get: { environment.books.preferences.textSize },
            set: { environment.books.preferences.textSize = $0 }
        )
    }

    /// The system text size moved by the person's own step, and one step larger in Focus Mode.
    private var readerTypeSize: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let current = all.firstIndex(of: systemTypeSize) else { return systemTypeSize }
        let step = environment.books.preferences.textSize.rawValue + (focus ? 1 : 0)
        let limit = all.firstIndex(of: .accessibility3) ?? (all.count - 1)
        return all[min(max(current + step, 0), limit)]
    }
}
