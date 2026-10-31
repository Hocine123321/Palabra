import SwiftUI

/// The shelf: one cover per book.
struct BookshelfView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let shelf = environment.books
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if shelf.library.books.isEmpty {
                    EmptyStateView(
                        systemImage: "books.vertical",
                        title: "No books available",
                        message: "Lessons are added to the app in updates."
                    )
                }
                ForEach(shelf.library.books) { book in
                    NavigationLink(value: BooksRoute.book(book.id)) {
                        BookCoverView(book: book, progress: shelf.progress(for: book))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bookCover.\(book.id)")
                }
                if !shelf.library.problems.isEmpty {
                    ErrorBanner(message: "Some lessons couldn't be loaded.", retryTitle: nil)
                        .accessibilityIdentifier("booksProblems")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background { ScreenBackdrop(style: .rich) }
        .navigationTitle("Books")
    }
}

/// A book's cover: its own paper, ornament and type, with the reading progress along the bottom.
struct BookCoverView: View {
    let book: Book
    let progress: BookShelf.Progress

    private var palette: Theme.Textbook.Palette { Theme.Textbook.palette(for: book.subject) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            palette.paper
            ornament
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label(book.subject.titleKey, systemImage: book.subject.systemImage)
                    .font(palette.font(.caption, weight: .bold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
                Text(verbatim: book.title)
                    .font(palette.font(.largeTitle, weight: .bold))
                    .foregroundStyle(palette.ink)
                if book.isEmpty {
                    Text("No lessons yet")
                        .font(palette.font(.subheadline))
                        .foregroundStyle(palette.inkSecondary)
                } else {
                    Text("\(book.lessonCount) lessons · \(book.pages.count) pages")
                        .font(palette.font(.subheadline))
                        .foregroundStyle(palette.inkSecondary)
                    ProgressView(value: progress.fraction)
                        .tint(palette.accent)
                        .accessibilityLabel(Text("\(progress.read) of \(progress.total) pages read"))
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 210)
        .clipShape(shape)
        .overlay(shape.stroke(palette.rule, lineWidth: 1))
        .environment(\.layoutDirection, book.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private var ornament: some View {
        switch book.subject {
        case .history:
            // A printed frame: two thin rules inset from the edge.
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(palette.rule, lineWidth: 1)
                    .padding(Theme.Spacing.sm + 2)
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(palette.rule.opacity(0.6), lineWidth: 0.5)
                    .padding(Theme.Spacing.md)
            }
            .accessibilityHidden(true)
        case .geography:
            // Atlas lines: a graticule and contour rings.
            AtlasLines()
                .stroke(palette.rule, lineWidth: 1)
                .accessibilityHidden(true)
        }
    }
}

private struct AtlasLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.30)
        for ring in 1...5 {
            let radius = rect.height * 0.15 * CGFloat(ring)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        for line in 1..<4 {
            let y = rect.minY + rect.height * CGFloat(line) / 4
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
