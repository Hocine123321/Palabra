import SwiftUI

/// The 2D layer over the 3D desk. Menu: one button per book (also what VoiceOver and UI tests use; the 3D books on the desk
/// do the same thing). Reading: back, text size, Focus Mode on top; page controls, tools and Memorize below. In Focus Mode
/// only a way out and the Magnifying Glass remain.
struct SceneHUD: View {
    let model: BooksSceneModel
    @Binding var path: [BooksRoute]
    let safeTop: CGFloat
    let safeBottom: CGFloat

    @Environment(AppEnvironment.self) private var environment

    private var state: SceneState { model.state }

    var body: some View {
        ZStack {
            if state.isReading {
                reading
            } else {
                menu
            }
            if let term = model.activeTerm {
                VStack {
                    Spacer()
                    TermCard(term: term) { model.closeTerm() }
                        .environment(\.bookPalette, palette)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Double(safeBottom) + (state.focus ? 84 : 160))
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.reduced(Motion.quick), value: model.activeTerm)
        .animation(Motion.reduced(Motion.quick), value: state.isReading)
        .animation(Motion.reduced(Motion.quick), value: state.focus)
        .animation(Motion.reduced(Motion.quick), value: state.recall)
        .environment(\.layoutDirection, .leftToRight)
        .overlay(alignment: .top) { noticeBanner }
    }

    private var palette: Theme.Textbook.Palette {
        Theme.Textbook.palette(for: environment.books.book(id: state.bookID ?? "")?.subject ?? .history)
    }

    // MARK: Menu

    private var menu: some View {
        VStack {
            HStack {
                Text("Books")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: 44)
                    .glassCapsule()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                textModeMenu
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, safeTop + Theme.Spacing.sm)
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(shelfBooks) { book in
                    shelfButton(book)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    /// The scene's list once it is up; the shelf's own until then, so the buttons never pop in late.
    private var shelfBooks: [SceneBookInfo] {
        if !state.books.isEmpty { return state.books }
        return environment.books.library.books.map {
            SceneBookInfo(id: $0.id, title: $0.title, subject: $0.subject.rawValue, pages: $0.pages.count, isRightToLeft: $0.isRightToLeft)
        }
    }

    private func shelfButton(_ info: SceneBookInfo) -> some View {
        let progress = model.progress(forBook: info.id)
        return Button {
            model.send(.openBook(id: info.id, pageID: nil))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: info.subject == "geography" ? "globe.europe.africa" : "building.columns")
                        .font(.body)
                        .foregroundStyle(Theme.accentDeep)
                    Text(verbatim: info.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if info.pages == 0 {
                    Text("No lessons yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(info.pages) pages")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let progress, progress.total > 0 {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.accent)
                        .accessibilityLabel(Text("\(progress.read) of \(progress.total) pages read"))
                } else {
                    Color.clear.frame(height: 4)
                }
            }
            .padding(Theme.Spacing.md - 2)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookCover.\(info.id)")
    }

    private var textModeMenu: some View {
        Menu {
            ForEach(environment.books.library.books) { book in
                Button {
                    path.append(.book(book.id))
                } label: {
                    Text(verbatim: book.title)
                }
            }
        } label: {
            hudIcon("text.alignleft", active: false)
        }
        .accessibilityLabel("Read as text")
        .accessibilityIdentifier("readAsText")
    }

    // MARK: Reading

    private var reading: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, safeTop + Theme.Spacing.xs)
            Spacer()
            VStack(spacing: Theme.Spacing.sm) {
                if state.recall && !state.focus { recallBar }
                bottomBar
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, max(safeBottom, Theme.Spacing.md))
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if state.focus {
                Button {
                    model.send(.setFocus(false))
                } label: {
                    Label("Exit Focus Mode", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(height: 44)
                        .glassCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focusExit")
                Spacer()
                hudButton(state.recall ? "magnifyingglass.circle.fill" : "magnifyingglass", label: "Magnifying Glass", id: "recallToggleFocus", active: state.recall) {
                    model.send(.setRecall(!state.recall))
                }
            } else {
                hudButton("chevron.backward", label: "Back to the shelf", id: "bookBack", active: false) {
                    model.send(.closeBook)
                }
                Spacer(minLength: 0)
                textSizeMenu
                hudButton("arrow.up.left.and.arrow.down.right", label: "Focus Mode", id: "focusButton", active: false) {
                    model.send(.setFocus(true))
                }
            }
        }
    }

    private var textSizeMenu: some View {
        Menu {
            Picker("Text size", selection: Binding(get: { state.textSize }, set: { model.send(.setTextSize($0)) })) {
                ForEach(ReaderTextSize.allCases) { size in
                    Text(size.titleKey).tag(size)
                }
            }
        } label: {
            hudIcon("textformat.size", active: false)
        }
        .accessibilityLabel("Text size")
        .accessibilityIdentifier("textSizeMenu")
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            pageButton(next: state.isRightToLeft, onLeft: true)
            Text(verbatim: "\u{2066}\(state.page) / \(state.pageCount)\u{2069}")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 56)
                .accessibilityLabel(Text("Page \(state.page) of \(state.pageCount)"))
                .accessibilityIdentifier("pageIndicator")
            pageButton(next: !state.isRightToLeft, onLeft: false)
            if !state.focus {
                Spacer(minLength: 0)
                toolButton("magnifyingglass", tool: "lens", label: "Magnifying glass tool", id: "toolLens")
                toolButton(state.bookmarkPageID == state.basePageID && state.basePageID != nil ? "bookmark.fill" : "bookmark", tool: "bookmark", label: "Bookmark", id: "toolBookmark")
                toolButton("ruler", tool: "ruler", label: "Ruler", id: "toolRuler")
                Button {
                    model.send(.setRecall(!state.recall))
                } label: {
                    Image(systemName: "brain")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(state.recall ? Color.white : Color.primary)
                        .frame(width: 44, height: 44)
                        .background(state.recall ? Theme.accent : Color.clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Memorize")
                .accessibilityAddTraits(state.recall ? .isSelected : [])
                .accessibilityIdentifier("recallToggle")
            }
        }
        .padding(Theme.Spacing.xs)
        .glassCapsule()
    }

    /// The arrows stay where the thumbs expect them; which one is "next" follows the book (Arabic turns toward the left).
    private func pageButton(next: Bool, onLeft: Bool) -> some View {
        let label: LocalizedStringKey = next ? "Next page" : "Previous page"
        return Button {
            model.send(next ? .next : .previous)
        } label: {
            Image(systemName: onLeft ? "chevron.left" : "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(next ? !state.canNext : !state.canPrev)
        .accessibilityLabel(label)
        .accessibilityIdentifier(next ? "pageNext" : "pagePrevious")
    }

    private func toolButton(_ symbol: String, tool: String, label: LocalizedStringKey, id: String) -> some View {
        let active = state.tool == tool
        return Button {
            model.send(.setTool(tool))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .background(active ? Theme.accent : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var recallBar: some View {
        let revealLabel: LocalizedStringKey = state.revealed ? "Hide answers on this page" : "Show answers on this page"
        return HStack(spacing: Theme.Spacing.sm) {
            Picker("Level", selection: Binding(get: { state.level }, set: { model.send(.setLevel($0)) })) {
                ForEach(RecallLevel.allCases) { level in
                    Text(level.titleKey).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recallLevel")
            Button {
                model.send(.togglePageReveal)
            } label: {
                Image(systemName: state.revealed ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealLabel)
            .accessibilityIdentifier("recallReveal")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .glassCard(cornerRadius: Theme.Radius.medium)
    }

    // MARK: Pieces

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            Text(LocalizedStringKey(notice))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassCapsule()
                .padding(.top, safeTop + 64)
                .transition(.opacity)
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    model.notice = nil
                }
                .accessibilityIdentifier("booksNotice")
        }
    }

    private func hudIcon(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .glassCapsule(tint: active ? Theme.accent : nil)
            .contentShape(Circle())
    }

    private func hudButton(_ symbol: String, label: LocalizedStringKey, id: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { hudIcon(symbol, active: active) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }
}
