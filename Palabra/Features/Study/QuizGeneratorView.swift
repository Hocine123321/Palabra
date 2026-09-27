import SwiftUI

/// Paste notes (any subject) → AI drafts a multiple-choice quiz → take it
/// inline with immediate feedback → see a final score. Kept as one
/// self-contained view (not persisted) since a generated quiz is meant for
/// one sitting, not a saved deck.
struct QuizGeneratorView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var subject = ""
    @State private var notes = ""
    @State private var isLoading = false
    @State private var error: AIError?
    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedOption: Int?
    @State private var hasAnswered = false
    @State private var score = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isLoading {
                loadingView
            } else if let error {
                failureView(error)
            } else if !questions.isEmpty && currentIndex < questions.count {
                quizView
            } else if !questions.isEmpty {
                resultsView
            } else {
                inputForm
            }
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !environment.hasAPIKey {
                    MissingAPIKeyPrompt(onOpenSettings: { environment.router.openSettings() })
                } else if environment.selectedModel == nil {
                    MissingModelPrompt(onOpenSettings: { environment.router.openSettings() })
                }
                GlassSurface {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Subject").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        TextField("e.g. Cell Biology, WWII", text: $subject)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(Theme.Spacing.md)
                }
                GlassSurface {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Paste your class notes").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        TextEditor(text: $notes)
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(Theme.Spacing.md)
                }
                Button {
                    Task { await generate() }
                } label: {
                    Text("Generate Quiz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !environment.hasAPIKey || environment.selectedModel == nil)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Building your quiz…").font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func failureView(_ error: AIError) -> some View {
        VStack {
            Spacer()
            ErrorBanner(
                message: LocalizedStringKey(error.userMessage),
                retryTitle: error.isRetryable ? "Retry" : nil,
                onRetry: error.isRetryable ? { Task { await generate() } } : nil,
                secondaryTitle: "Edit notes",
                onSecondary: { self.error = nil }
            )
            .padding(Theme.Spacing.md)
            Spacer()
        }
    }

    private var quizView: some View {
        let question = questions[currentIndex]
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Question \(currentIndex + 1) of \(questions.count)").font(.caption).foregroundStyle(Theme.inkSecondary)
                Text(question.question).font(Theme.Font.serif(20)).foregroundStyle(Theme.ink)

                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    optionRow(question: question, optionIndex: optionIndex, option: option)
                }

                if hasAnswered {
                    if let explanation = question.explanation, !explanation.isEmpty {
                        Text(explanation).font(.footnote).foregroundStyle(Theme.inkSecondary)
                    }
                    Button(currentIndex + 1 == questions.count ? "See Results" : "Next Question") {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func optionRow(question: QuizQuestion, optionIndex: Int, option: String) -> some View {
        let isCorrect = optionIndex == question.correctIndex
        let isSelected = optionIndex == selectedOption
        return Button {
            guard !hasAnswered else { return }
            selectedOption = optionIndex
            hasAnswered = true
            if isCorrect { score += 1 }
        } label: {
            HStack {
                Text(option).foregroundStyle(Theme.ink)
                Spacer()
                if hasAnswered && (isSelected || isCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isCorrect ? Color.green : Theme.error)
                }
            }
            .padding(Theme.Spacing.md)
            .background(rowBackground(isSelected: isSelected, isCorrect: isCorrect), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
    }

    private func rowBackground(isSelected: Bool, isCorrect: Bool) -> Color {
        guard hasAnswered else { return Theme.surface }
        if isCorrect { return Color.green.opacity(0.15) }
        if isSelected { return Theme.error.opacity(0.15) }
        return Theme.surface
    }

    private var resultsView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Score").font(.subheadline).foregroundStyle(Theme.inkSecondary)
            Text("\(score) / \(questions.count)").font(Theme.Font.serif(40)).foregroundStyle(Theme.ink)
            Button("Try New Notes") { reset() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(Theme.Spacing.md)
    }

    private func advance() {
        selectedOption = nil
        hasAnswered = false
        withAnimation(Motion.standard) { currentIndex += 1 }
    }

    private func reset() {
        questions = []
        currentIndex = 0
        selectedOption = nil
        hasAnswered = false
        score = 0
        notes = ""
        error = nil
    }

    private func generate() async {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            error = .missingAPIKey
            return
        }
        guard let model = environment.selectedModel else {
            error = environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? "")
            return
        }
        isLoading = true
        error = nil
        let result = await environment.ai.generateQuiz(from: notes, subject: subject, apiKey: apiKey, model: model, language: environment.aiLanguage)
        isLoading = false
        switch result {
        case .success(let generated):
            questions = generated
            currentIndex = 0
            score = 0
        case .failure(let err):
            error = err
        }
    }
}
