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
                    BookPageView(page: book.pages[i]).tag(i)
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
