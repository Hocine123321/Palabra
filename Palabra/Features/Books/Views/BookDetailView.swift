import SwiftUI

/// A book's front page: where to continue, and every chapter and lesson.
struct BookDetailView: View {
    let bookID: String

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let book = environment.books.book(id: bookID) {
            content(book)
        } else {
            EmptyStateView(systemImage: "book.closed", title: "No books available", message: "Lessons are added to the app in updates.")
                .frame(maxHeight: .infinity)
                .background { ScreenBackdrop(style: .calm) }
        }
    }

    private func content(_ book: Book) -> some View {
        let shelf = environment.books
        let progress = shelf.progress(for: book)
        let direction: LayoutDirection = book.isRightToLeft ? .rightToLeft : .leftToRight
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                BookCoverView(book: book, progress: progress)
                if book.isEmpty {
                    EmptyStateView(
                        systemImage: "book.closed",
                        title: "No lessons yet",
                        message: "Lessons are added to the app in updates."
                    )
                } else {
                    NavigationLink(value: BooksRoute.reader(bookID: book.id, pageID: shelf.lastPageID(bookID: book.id))) {
                        Label(progress.read > 0 ? LocalizedStringKey("Continue reading") : LocalizedStringKey("Start reading"), systemImage: "book")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("bookStart")
                    ForEach(book.chapters) { chapter in
                        chapterSection(chapter, in: book)
                    }
                }
            }
            .environment(\.layoutDirection, direction)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background { ScreenBackdrop(style: .calm) }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chapterSection(_ chapter: BookChapter, in book: Book) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            Text(verbatim: chapter.title)
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if chapter.lessons.isEmpty {
                Text("No lessons in this chapter yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(chapter.lessons) { lesson in
                lessonRow(lesson, in: book)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lessonRow(_ lesson: BookLesson, in book: Book) -> some View {
        let progress = environment.books.progress(for: lesson, in: book)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            NavigationLink(value: BooksRoute.reader(bookID: book.id, pageID: lesson.pages.first?.id)) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                    Text(verbatim: lesson.title)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let summary = lesson.summary {
                        Text(verbatim: summary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Text("\(progress.read) of \(progress.total) pages read")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(lesson.pages.isEmpty)
            .accessibilityIdentifier("lessonRow.\(lesson.id)")
            if !lesson.notes.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                        ForEach(lesson.notes.indices, id: \.self) { i in
                            Text(verbatim: lesson.notes[i])
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                } label: {
                    Text("Transcription notes (\(lesson.notes.count))")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.accentDeep)
                .accessibilityIdentifier("lessonNotes.\(lesson.id)")
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }
}
