import SwiftUI

/// The four detail sections, addressable by id for the jump bar.
enum WordSection: String, CaseIterable, Identifiable {
    case examples, meaning, forms, similar

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .examples: return "Examples"
        case .meaning: return "Meaning"
        case .forms: return "Forms"
        case .similar: return "Similar"
        }
    }
}

/// Renders the four required sections (examples, meaning & usage, forms,
/// similar words) for a `WordContent`. Shared by the Add-word preview sheet
/// and the word detail screen. `Accessory` is an optional trailing view next
/// to the headword — the word detail screen uses it for the pronunciation
/// button; the preview sheet (before the word is even saved, so there's
/// nothing to pronounce yet) uses the plain `init(content:)` below instead.
struct WordContentView<Accessory: View>: View {
    let content: WordContent
    @ViewBuilder var accessory: () -> Accessory
    @State private var revealedExamples: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(content.word)
                    .font(Theme.Font.serif(32))
                    .foregroundStyle(Theme.ink)
                accessory()
            }

            SectionCard(title: "Example Paragraphs", systemImage: "text.quote") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(Array(content.examples.enumerated()), id: \.offset) { index, example in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Chip(text: example.context)
                            Text(example.spanish)
                                .foregroundStyle(Theme.ink)
                            if revealedExamples.contains(index) {
                                Text(example.english)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .transition(.opacity)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExample(index) }
                        .accessibilityAddTraits(.isButton)
                        if index < content.examples.count - 1 { Divider() }
                    }
                }
            }
            .id(WordSection.examples)

            SectionCard(title: "Meaning & Usage", systemImage: "text.book.closed") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FlowChips(items: content.meaning.translations)
                    Text(content.meaning.explanation)
                        .foregroundStyle(Theme.ink)
                    Chip(text: content.usage.register)
                    Text(content.usage.explanation)
                        .foregroundStyle(Theme.ink)
                    if let nuance = content.usage.nuance {
                        Text(nuance)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .id(WordSection.meaning)

            SectionCard(title: "Word Forms", systemImage: "textformat") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(content.forms.partOfSpeech.capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(content.forms.groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(group.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            FlowChips(items: group.items.map(formLabel))
                        }
                    }
                }
            }
            .id(WordSection.forms)

            SectionCard(title: "Similar Words", systemImage: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(content.similarWords, id: \.word) { similar in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(similar.word)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(similar.difference)
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            .id(WordSection.similar)
        }
    }

    private func toggleExample(_ index: Int) {
        withAnimation(Motion.quick) {
            if revealedExamples.contains(index) {
                revealedExamples.remove(index)
            } else {
                revealedExamples.insert(index)
            }
        }
    }

    private func formLabel(_ item: WordContent.Forms.FormGroup.FormItem) -> String {
        guard let note = item.note, !note.isEmpty else { return item.form }
        return "\(item.form) (\(note))"
    }
}

extension WordContentView where Accessory == EmptyView {
    /// No trailing accessory next to the headword — used by the Add-word
    /// preview sheet, where the word isn't saved yet so there's nothing to
    /// attach a pronunciation button to.
    init(content: WordContent) {
        self.content = content
        self.accessory = { EmptyView() }
    }
}
