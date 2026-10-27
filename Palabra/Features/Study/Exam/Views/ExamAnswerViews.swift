import SwiftUI

/// Multiple choice. After the answer the right option turns green and a wrong pick red.
struct ExamChoiceView: View {
    let options: [String]
    let correct: Int
    /// The picked option once answered; nil while asking.
    let chosen: Int?
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { onPick(index) } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(verbatim: option)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if let symbol = symbol(index) {
                            Image(systemName: symbol).foregroundStyle(tint(index))
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fill(index), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .strokeBorder(tint(index).opacity(chosen == nil || !(index == correct || index == chosen) ? 0 : 1), lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil)
                .accessibilityIdentifier("examOption-\(index)")
            }
        }
    }

    private func fill(_ index: Int) -> Color {
        guard chosen != nil else { return Theme.fill.opacity(0.7) }
        if index == correct { return Theme.success.opacity(0.2) }
        if index == chosen { return Theme.error.opacity(0.18) }
        return Theme.fill.opacity(0.5)
    }

    private func tint(_ index: Int) -> Color {
        if index == correct { return Theme.success }
        return index == chosen ? Theme.error : Theme.inkSecondary
    }

    private func symbol(_ index: Int) -> String? {
        guard chosen != nil else { return nil }
        if index == correct { return "checkmark.circle.fill" }
        return index == chosen ? "xmark.circle.fill" : nil
    }
}

/// A typed answer (a Spanish word or its meaning), with a bar for the accented letters.
struct ExamTypedView: View {
    let session: ExamSession
    let english: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TextField(english ? LocalizedStringKey("Type the meaning") : LocalizedStringKey("Type in Spanish"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(submit)
                .onChange(of: text) { _, new in if new.count > 120 { text = String(new.prefix(120)) } }
                .padding(Theme.Spacing.md)
                .innerFill()
                .accessibilityIdentifier("examTypedField")
            if !english { accentBar }
            Button(action: submit) { Text("Check") }
                .buttonStyle(.primary)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("examCheckButton")
            Button { session.giveUp() } label: { Text("I don't know") }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("examGiveUpButton")
        }
        .onAppear { focused = true }
    }

    private var accentBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"], id: \.self) { letter in
                Button { text.append(letter) } label: {
                    Text(verbatim: letter)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        focused = false
        session.answerTyped(trimmed)
    }
}

/// Put shuffled words in order: tap a word to place it, tap it in the answer to take it back.
struct ExamReorderView: View {
    let session: ExamSession
    let tokens: [String]
    @State private var placed: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            FlowLayout {
                ForEach(placed, id: \.self) { index in
                    chip(tokens[index], placed: true) { placed.removeAll { $0 == index } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(Theme.Spacing.sm)
            .innerFill()
            .accessibilityIdentifier("examReorderAnswer")

            FlowLayout {
                ForEach(Array(tokens.indices), id: \.self) { index in
                    if !placed.contains(index) {
                        chip(tokens[index], placed: false) { placed.append(index) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { session.answerOrder(placed.map { tokens[$0] }) } label: { Text("Check") }
                .buttonStyle(.primary)
                .disabled(placed.count != tokens.count)
                .accessibilityIdentifier("examCheckButton")
            Button { session.giveUp() } label: { Text("I don't know") }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("examGiveUpButton")
        }
        // Spanish reads left to right whatever the app language is.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func chip(_ text: String, placed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(placed ? Theme.accentSoft : Theme.fill, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(placed ? "examPlacedToken" : "examToken")
    }
}

/// Match each word with its meaning: tap one on the left, then its partner on the right.
struct ExamMatchView: View {
    let session: ExamSession
    let pairs: [ExamQuestion.Pair]
    @State private var rightOrder: [Int] = []
    @State private var selectedLeft: Int?
    @State private var matched: Set<Int> = []
    @State private var mistakes = 0
    @State private var wrongRight: Int?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(pairs.indices, id: \.self) { index in
                    cell(pairs[index].left, state: leftState(index)) {
                        guard !matched.contains(index) else { return }
                        selectedLeft = index
                        wrongRight = nil
                    }
                    .accessibilityIdentifier("examMatchLeft-\(index)")
                }
            }
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rightOrder, id: \.self) { index in
                    cell(pairs[index].right, state: rightState(index)) { pickRight(index) }
                        .accessibilityIdentifier("examMatchRight-\(index)")
                }
            }
        }
        .onAppear {
            guard rightOrder.isEmpty else { return }
            var order = Array(pairs.indices)
            // Never start with every pair already side by side.
            for _ in 0..<5 {
                order.shuffle()
                if order != Array(pairs.indices) || pairs.count < 2 { break }
            }
            rightOrder = order
        }
    }

    private enum CellState { case idle, selected, matched, wrong }

    private func leftState(_ index: Int) -> CellState {
        if matched.contains(index) { return .matched }
        return selectedLeft == index ? .selected : .idle
    }

    private func rightState(_ index: Int) -> CellState {
        if matched.contains(index) { return .matched }
        return wrongRight == index ? .wrong : .idle
    }

    private func pickRight(_ index: Int) {
        guard let left = selectedLeft, !matched.contains(index) else { return }
        if left == index {
            matched.insert(index)
            selectedLeft = nil
            wrongRight = nil
            if matched.count == pairs.count { session.answerMatch(mistakes: mistakes) }
        } else {
            mistakes += 1
            wrongRight = index
        }
    }

    private func cell(_ text: String, state: CellState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, Theme.Spacing.sm)
                .background(color(state), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(state == .selected ? Theme.accent : Color.clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .disabled(state == .matched)
    }

    private func color(_ state: CellState) -> Color {
        switch state {
        case .idle, .selected: return Theme.fill.opacity(0.7)
        case .matched: return Theme.success.opacity(0.22)
        case .wrong: return Theme.error.opacity(0.2)
        }
    }
}

/// Say the word: the phone listens and compares what it heard.
struct ExamSpokenView: View {
    let session: ExamSession
    let questionID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var listening = false
    @State private var denied = false
    @State private var heardNothing = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button { Task { await listen() } } label: {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 96, height: 96)
                    .background(listening ? Theme.accentDeep : Theme.accent, in: Circle())
                    .symbolEffect(.variableColor.iterative, isActive: listening)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening ? Text("Stop listening") : Text("Say it"))
            .accessibilityIdentifier("examMicButton")
            Text(listening ? LocalizedStringKey("Listening…") : LocalizedStringKey("Tap, then say it in Spanish."))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if heardNothing {
                Text("I didn't catch that. Try again.").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentDeep)
            }
            if denied {
                Text("Allow the microphone and speech recognition for Palabra in Settings to answer out loud.")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center)
            }
            Button { environment.speech.stop(); session.skipWithoutScore() } label: { Text("Skip this question") }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("examSkipButton")
        }
        .frame(maxWidth: .infinity)
        .onDisappear { environment.speech.stop() }
    }

    private func listen() async {
        if listening {
            environment.speech.stop()
            return
        }
        heardNothing = false
        guard await environment.speech.requestAuthorization() else {
            denied = true
            return
        }
        denied = false
        listening = true
        let heard = await environment.speech.listen(timeout: 8)
        listening = false
        // The person skipped or left while the phone was listening.
        guard session.phase == .asking, session.current?.id == questionID else { return }
        if let heard, !heard.isEmpty { session.answerSpoken(heard) } else { heardNothing = true }
    }
}

/// A sentence the person writes. AI checks it; when AI can't, the person says how it went.
struct ExamWrittenView: View {
    let session: ExamSession
    let reference: String?
    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TextField("Write it in Spanish", text: $text, axis: .vertical)
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .onChange(of: text) { _, new in if new.count > 300 { text = String(new.prefix(300)) } }
                .padding(Theme.Spacing.md)
                .innerFill()
                .disabled(session.isGrading || session.needsSelfCheck)
                .accessibilityIdentifier("examWrittenField")
            if session.isGrading {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Checking your answer…").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
            } else if session.needsSelfCheck {
                selfCheck
            } else {
                Button { Task { await session.answerWritten(text) } } label: { Text("Check") }
                    .buttonStyle(.primary)
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("examCheckButton")
                Button { session.giveUp() } label: { Text("I don't know") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityIdentifier("examGiveUpButton")
            }
        }
    }

    private var selfCheck: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("AI couldn't check this one. Compare it yourself and say how it went.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if let reference, !reference.isEmpty {
                Text("Example").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                Text(verbatim: reference).font(.body).foregroundStyle(Theme.ink)
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button { session.selfGrade(0) } label: { Text("Wrong").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassAction)
                    .accessibilityIdentifier("selfGradeWrong")
                Button { session.selfGrade(0.5) } label: { Text("Almost").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassAction)
                    .accessibilityIdentifier("selfGradeAlmost")
                Button { session.selfGrade(1) } label: { Text("Right").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassAction)
                    .accessibilityIdentifier("selfGradeRight")
            }
        }
    }
}
