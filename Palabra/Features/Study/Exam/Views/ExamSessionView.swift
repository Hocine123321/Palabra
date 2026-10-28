import SwiftUI

/// Runs one exam: builds the questions (asking the AI for fresh sentences first when that is on), shows them one at a
/// time, saves the result, then shows it.
struct ExamSessionView: View {
    let config: ExamConfig
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var session: ExamSession?
    @State private var preparing = true
    /// A localization key: something the person should know about how the exam was made.
    @State private var notice: String?
    @State private var speaker = SentenceSpeaker()
    @State private var savedID: UUID?
    @State private var confirmEnd = false

    private var running: Bool { session != nil && session?.phase != .finished }

    var body: some View {
        ZStack {
            ScreenBackdrop(style: .calm)
            if let session {
                content(session)
            } else if preparing {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    Text(config.useAI ? LocalizedStringKey("Writing your questions…") : LocalizedStringKey("Preparing your exam…"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else {
                ScrollView {
                    EmptyStateView(
                        systemImage: "questionmark.circle",
                        title: "Couldn't make this exam",
                        message: "There aren't enough words for the chosen skills. Pick other skills or words."
                    )
                }
            }
        }
        .navigationTitle("Exam")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(running)
        .toolbar {
            if running {
                ToolbarItem(placement: .topBarLeading) {
                    Button("End Exam") { confirmEnd = true }
                        .accessibilityIdentifier("endExamButton")
                }
            }
        }
        .confirmationDialog("End the exam now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and See Results", role: .destructive) {
                if let session, session.answeredCount > 0 { session.endEarly() } else { path.removeLast() }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Questions you haven't answered are left out.")
        }
        .task {
            guard session == nil, preparing else { return }
            await prepare()
        }
        .onChange(of: session?.phase) { _, phase in
            if phase == .finished { saveOnce() }
        }
        .onDisappear {
            speaker.stop()
            environment.speech.stop()
            // Popped in the middle (the swipe back): what was answered is kept as a result. Switching to another
            // tab also disappears this view but leaves the route on the stack, and then the exam just waits.
            if let session, session.phase != .finished, !path.contains(.exam(config)) {
                session.endEarly()
                saveOnce()
            }
        }
    }

    @ViewBuilder
    private func content(_ session: ExamSession) -> some View {
        if session.phase == .finished {
            ExamSummaryView(
                records: session.records, config: config, duration: session.duration,
                notice: notice, autoCoach: config.useAI, path: $path
            )
        } else if let question = session.current {
            ExamQuestionView(session: session, question: question, speaker: speaker)
                .id(question.id)
        }
    }

    // MARK: - Building

    private func prepare() async {
        let words = environment.examWords()
        let stats = environment.exams.wordStats(lastExams: 30)
        let capabilities = ExamCapabilities(speech: environment.speech.isAvailable)
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let ai = config.useAI ? environment.examAI() : nil
        var items: [UUID: ExamAIItem] = [:]

        if config.useAI, ai == nil {
            notice = "AI isn't set up, so this exam uses only your own words."
        } else if let ai {
            // Same seed, same words: ask the AI for fresh sentences for exactly the words that will be asked.
            var planner = ExamBuilder(rng: SeededGenerator(seed: seed), pool: words, capabilities: capabilities)
            var seen = Set<UUID>()
            let planned = planner.plannedWords(config: config, stats: stats).filter { seen.insert($0.id).inserted }
            switch await Self.freshItems(ai, for: planned) {
            case .success(let fresh)?: items = fresh
            case .failure?: notice = "AI couldn't be reached, so this exam uses only your own words."
            case nil: notice = "AI took too long, so this exam uses only your own words."
            }
        }

        var builder = ExamBuilder(rng: SeededGenerator(seed: seed), pool: words, capabilities: capabilities, aiItems: items)
        let questions = builder.build(config: config, stats: stats)
        preparing = false
        guard !questions.isEmpty else { return }
        session = ExamSession(questions: questions, config: config, grader: config.useAI ? ai : nil)
    }

    /// The exam must not wait on a slow AI: after `aiWait` seconds it starts with the person's own words (nil = gave up).
    nonisolated static let aiWait: Double = 15

    nonisolated private static func freshItems(_ ai: ExamAI, for words: [ExamWord]) async -> Result<[UUID: ExamAIItem], AIError>? {
        await withTaskGroup(of: Result<[UUID: ExamAIItem], AIError>?.self) { group in
            group.addTask { await ai.freshItems(for: words) }
            group.addTask {
                try? await Task.sleep(for: .seconds(aiWait))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func saveOnce() {
        guard savedID == nil, let session, !session.records.isEmpty else { return }
        savedID = environment.exams.save(config: config, records: session.records, duration: session.duration, now: Date())?.id
    }
}
