import SwiftUI

/// Past exams, and the words that keep going wrong.
struct ExamHistoryView: View {
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var exams: [ExamResult] = []
    @State private var weakWords: [WeakWord] = []
    @State private var confirmDeleteAll = false

    struct WeakWord: Identifiable, Equatable {
        let id: UUID
        let headword: String
        let accuracy: Double
        let attempts: Int
    }

    var body: some View {
        ZStack {
            ScreenBackdrop(style: .calm)
            if exams.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "clock.arrow.circlepath",
                        title: "No exams yet",
                        message: "Finished exams show up here, with the words that keep going wrong."
                    )
                }
            } else {
                List {
                    if !weakWords.isEmpty { weakSection }
                    Section {
                        ForEach(exams, id: \.id) { exam in
                            Button { path.append(.examResult(exam.id)) } label: { row(exam) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("examHistoryRow")
                        }
                        .onDelete { offsets in
                            for index in offsets { environment.exams.delete(id: exams[index].id) }
                            reload()
                        }
                    } header: {
                        Text("Exams")
                    }
                    .themedSection()
                }
                .glassScreen()
            }
        }
        .navigationTitle("Past Exams")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !exams.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDeleteAll = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete All Exams")
                        .accessibilityIdentifier("deleteAllExamsButton")
                }
            }
        }
        .confirmationDialog("Delete all exam history?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                environment.exams.deleteAll()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { reload() }
    }

    private var weakSection: some View {
        Section {
            ForEach(weakWords) { word in
                HStack {
                    Text(verbatim: word.headword).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(verbatim: "\(Int((word.accuracy * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.error)
                }
            }
            Button {
                var config = ExamConfig()
                config.source = .words(weakWords.map(\.id))
                config.questionCount = min(max(weakWords.count, 1), 30)
                path.append(.exam(config))
            } label: {
                Label("Practice These Words", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
            }
            .accessibilityIdentifier("practiceWeakButton")
        } header: {
            Text("Needs practice")
        }
        .themedSection()
    }

    private func row(_ exam: ExamResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(verbatim: "\(Int((exam.fraction * 100).rounded()))%")
                .font(Theme.Font.heading.monospacedDigit())
                .foregroundStyle(exam.fraction >= 0.7 ? Theme.success : (exam.fraction >= 0.5 ? Theme.accentDeep : Theme.error))
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Text("\(exam.questionCount) questions")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func reload() {
        exams = environment.exams.recent(limit: SwiftDataExamRepository.maxResults)
        // Words tested at least twice in the last exams, worst first.
        var names: [UUID: String] = [:]
        for exam in exams.prefix(30) {
            for record in exam.records where record.involvedWordIDs == nil { names[record.wordID] = record.headword }
        }
        let stats = environment.exams.wordStats(lastExams: 30)
        // Words deleted from the library since are left out.
        let existing = Set(environment.repository.wordSummaries().map(\.id))
        weakWords = stats
            .filter { existing.contains($0.key) && $0.value.attempts >= 2 && $0.value.accuracy < 0.7 }
            .compactMap { id, stat in
                names[id].map { WeakWord(id: id, headword: $0, accuracy: stat.accuracy, attempts: stat.attempts) }
            }
            .sorted { $0.accuracy < $1.accuracy }
            .prefix(10)
            .map { $0 }
    }
}

/// A saved exam.
struct ExamResultView: View {
    let examID: UUID
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var exam: ExamResult?
    @State private var loaded = false

    var body: some View {
        ZStack {
            ScreenBackdrop(style: .calm)
            if let exam {
                ExamSummaryView(
                    records: exam.records, config: exam.config ?? ExamConfig(),
                    duration: exam.durationSeconds, path: $path
                )
            } else if loaded {
                ScrollView {
                    EmptyStateView(systemImage: "questionmark.circle", title: "Exam not found", message: "It may have been deleted.")
                }
            }
        }
        .navigationTitle("Exam")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            exam = environment.exams.result(id: examID)
            loaded = true
        }
    }
}
