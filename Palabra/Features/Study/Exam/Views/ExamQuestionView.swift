import SwiftUI

/// A round speaker button that reads Spanish text aloud with the phone's own voice (free, offline).
struct ExamSpeakButton: View {
    let text: String
    let speaker: SentenceSpeaker

    var body: some View {
        Button { speaker.toggle(text) } label: {
            Image(systemName: speaker.speaking == text ? "stop.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.glassIcon)
        .accessibilityLabel(speaker.speaking == text ? Text("Stop") : Text("Hear it"))
        .accessibilityIdentifier("examSpeakButton")
    }
}

/// One question: the prompt, the way to answer it, and after answering the result with a Next button.
struct ExamQuestionView: View {
    let session: ExamSession
    let question: ExamQuestion
    let speaker: SentenceSpeaker

    private var answered: Bool { session.phase == .answered }
    private var isLast: Bool { session.answeredCount >= session.total }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                promptCard
                if answered { feedback } else { answerArea }
            }
            .padding(Theme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if answered {
                Button { session.next() } label: {
                    Text(isLast ? LocalizedStringKey("See Results") : LocalizedStringKey("Next"))
                }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                .accessibilityIdentifier("examNextButton")
            }
        }
        .onAppear {
            // Listening questions start by playing.
            if let text = question.speakText, !answered { speaker.toggle(text) }
        }
    }

    // MARK: - Header and prompt

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Chip(titleKey: LocalizedStringKey(question.kind.skill.title))
                Spacer()
                Text("\(min(session.answeredCount + (answered ? 0 : 1), session.total)) of \(session.total)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityIdentifier("examProgressLabel")
            }
            StudyProgressTrack(fraction: session.progress)
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(LocalizedStringKey(question.kind.instruction))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            if let text = question.speakText {
                // Listening: the word is not shown, only played.
                HStack {
                    Spacer()
                    ExamSpeakButton(text: text, speaker: speaker)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            if !question.subject.isEmpty {
                Text(verbatim: question.subject)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("examSubject")
            }
            if let hint = question.hint, !hint.isEmpty {
                Text(verbatim: hint).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            if showsHeadwordSpeaker {
                ExamSpeakButton(text: question.headword, speaker: speaker)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Questions that show the Spanish word can read it out.
    private var showsHeadwordSpeaker: Bool {
        question.kind == .meaningChoice || question.kind == .typeMeaning || question.kind == .similarChoice
    }

    // MARK: - Answering

    @ViewBuilder
    private var answerArea: some View {
        switch question.format {
        case .choice(let options, let correct):
            ExamChoiceView(options: options, correct: correct, chosen: nil) { session.answerChoice($0) }
        case .typed(_, let english):
            ExamTypedView(session: session, english: english)
        case .reorder(let tokens, _):
            ExamReorderView(session: session, tokens: tokens)
        case .match(let pairs):
            ExamMatchView(session: session, pairs: pairs)
        case .spoken:
            ExamSpokenView(session: session, questionID: question.id)
        case .written(let reference):
            ExamWrittenView(session: session, reference: reference)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var feedback: some View {
        if let record = session.lastRecord {
            // A multiple-choice question keeps showing its options, marked.
            if case .choice(let options, let correct) = question.format {
                ExamChoiceView(options: options, correct: correct, chosen: options.firstIndex(of: record.given) ?? -1) { _ in }
            }
            resultCard(record)
        }
    }

    private func resultCard(_ record: ExamAnswerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text(verdictTitle(record))
            } icon: {
                Image(systemName: record.isCorrect ? "checkmark.circle.fill" : (record.isPartial ? "circle.lefthalf.filled" : "xmark.circle.fill"))
            }
            .font(Theme.Font.heading)
            .foregroundStyle(record.isCorrect ? Theme.success : (record.isPartial ? Theme.accentDeep : Theme.error))
            .accessibilityIdentifier("examVerdict")

            if let note = verdictNote(record) {
                Text(note).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            if !record.isCorrect, !record.given.isEmpty, question.kind != .matchPairs, !isChoice {
                labelled("Your answer", record.given)
            }
            if !record.isCorrect, question.kind != .matchPairs, !record.expected.isEmpty {
                labelled("Answer", record.expected)
            }
            if let feedback = record.feedback, !feedback.isEmpty {
                Text(verbatim: feedback).font(.subheadline).foregroundStyle(Theme.ink)
            }
            if let explanation = question.explanation, !explanation.isEmpty {
                Text(verbatim: explanation).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            if !isMatch {
                ExamSpeakButton(text: question.speakText ?? question.headword, speaker: speaker)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var isChoice: Bool {
        if case .choice = question.format { return true }
        return false
    }

    private var isMatch: Bool {
        if case .match = question.format { return true }
        return false
    }

    private func labelled(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Text(verbatim: text).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
        }
    }

    private func verdictTitle(_ record: ExamAnswerRecord) -> LocalizedStringKey {
        if record.isCorrect { return "Correct!" }
        return record.isPartial ? "Almost" : "Not quite"
    }

    private func verdictNote(_ record: ExamAnswerRecord) -> LocalizedStringKey? {
        guard !record.isCorrect, case .typed = question.format else {
            if question.kind == .matchPairs, !record.isCorrect { return "Some pairs took more than one try." }
            return nil
        }
        switch session.lastTypedKind {
        case .accentsMissed: return "Mind the accents."
        case .typo: return "Close: check the spelling."
        default: return nil
        }
    }
}
