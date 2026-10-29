import SwiftUI

/// The strip at the foot of the reader: contents and Focus Mode on the sides, previous / page / next in the middle.
/// In Focus Mode the sides become "exit" and the Magnifying Glass switch, and everything else stays out of the way.
struct ReaderControlBar: View {
    let book: Book
    @Binding var index: Int
    @Binding var focus: Bool
    @Binding var showContents: Bool

    @Environment(\.bookPalette) private var palette
    @Environment(ReaderContext.self) private var context

    private var count: Int { book.pages.count }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if focus {
                sideControl("arrow.down.right.and.arrow.up.left", label: "Exit Focus Mode", id: "focusExit") { setFocus(false) }
            } else {
                sideControl("list.bullet", label: "Contents", id: "contentsButton") { showContents = true }
            }
            Spacer(minLength: 0)
            pageButton(
                symbol: "chevron.backward", label: "Previous page", id: "pagePrevious",
                enabled: index > 0, key: book.isRightToLeft ? .rightArrow : .leftArrow
            ) { go(index - 1) }
            Text(verbatim: "\u{2066}\(index + 1) / \(count)\u{2069}")
                .font(palette.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(minWidth: 64)
                .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
                .accessibilityIdentifier("pageIndicator")
            pageButton(
                symbol: "chevron.forward", label: "Next page", id: "pageNext",
                enabled: index < count - 1, key: book.isRightToLeft ? .leftArrow : .rightArrow
            ) { go(index + 1) }
            Spacer(minLength: 0)
            if focus {
                sideControl(
                    context.recall.isEnabled ? "magnifyingglass.circle.fill" : "magnifyingglass",
                    label: "Magnifying Glass", id: "recallToggleFocus"
                ) { context.recall.setEnabled(!context.recall.isEnabled) }
            } else {
                sideControl("arrow.up.left.and.arrow.down.right", label: "Focus Mode", id: "focusButton") { setFocus(true) }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background {
            palette.paper.opacity(0.96).ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }

    private func setFocus(_ on: Bool) {
        Motion.animate { focus = on }
    }

    private func go(_ target: Int) {
        let clamped = min(max(target, 0), count - 1)
        Motion.animate { index = clamped }
    }

    private func sideControl(_ symbol: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func pageButton(
        symbol: String, label: LocalizedStringKey, id: String, enabled: Bool, key: KeyEquivalent, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? palette.accent : palette.inkSecondary.opacity(0.5))
        .disabled(!enabled)
        .keyboardShortcut(key, modifiers: [])
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Shown while Magnifying Glass is on: how much to hide, and a way to reveal or hide the whole page at once.
struct RecallBar: View {
    let pageID: String

    @Environment(\.bookPalette) private var palette
    @Environment(ReaderContext.self) private var context

    var body: some View {
        let revealed = context.recall.isPageRevealed(pageID)
        let levelBinding = Binding<RecallLevel>(
            get: { context.recall.level },
            set: { context.recall.setLevel($0) }
        )
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return VStack(spacing: Theme.Spacing.sm) {
            Picker("Recall level", selection: levelBinding) {
                ForEach(RecallLevel.allCases) { level in
                    Text(level.titleKey).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recallLevel")
            HStack {
                Text("Tap a hidden answer to reveal it.")
                    .font(.caption)
                    .foregroundStyle(palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if revealed { context.recall.hidePage(pageID) } else { context.recall.revealPage(pageID) }
                } label: {
                    Label(revealed ? LocalizedStringKey("Hide all") : LocalizedStringKey("Reveal all"), systemImage: revealed ? "eye.slash" : "eye")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("recallRevealAll")
            }
        }
        .padding(Theme.Spacing.md)
        .background(palette.paperEdge, in: shape)
        .overlay(shape.stroke(palette.rule, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.md)
    }
}

/// The compact explanation of a highlighted term. Sits above the controls, so the lesson stays readable behind it.
struct TermCard: View {
    let term: ActiveTerm
    let onClose: () -> Void

    @Environment(\.bookPalette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verbatim: term.term)
                    .font(palette.font(.headline, weight: .bold))
                    .foregroundStyle(palette.accent)
                Text(verbatim: term.definition)
                    .font(palette.font(.callout))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("termClose")
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(palette.paperEdge, in: shape)
        .overlay(shape.stroke(palette.accent.opacity(0.6), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("termCard")
    }
}

/// Every chapter, lesson and page of the book, to jump to any of them.
struct BookContentsView: View {
    let book: Book
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.bookPalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                ForEach(book.chapters) { chapter in
                    Section {
                        ForEach(chapter.lessons) { lesson in
                            Text(verbatim: lesson.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.inkSecondary)
                                .listRowBackground(palette.paper)
                            ForEach(lesson.pages) { page in
                                row(page)
                            }
                        }
                    } header: {
                        Text(verbatim: chapter.title)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(palette.accent)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.paper)
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ page: BookPage) -> some View {
        let isCurrent = book.index(ofPage: page.id) == currentIndex
        return Button {
            if let target = book.index(ofPage: page.id) { onSelect(target) }
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.sm + 4) {
                Text(verbatim: "\(page.number)")
                    .font(palette.font(.subheadline, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 24)
                Text(verbatim: page.page.title)
                    .font(palette.font(.body))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "bookmark.fill").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? palette.accent.opacity(0.12) : palette.paper)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("contentsPage.\(page.number)")
    }
}
