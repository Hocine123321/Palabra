import SwiftUI

/// The result of an exam: the score, how each skill went, the missed words, and what to do about them. Used right
/// after an exam and when opening a saved one.
struct ExamSummaryView: View {
    let records: [ExamAnswerRecord]
    let config: ExamConfig
    let duration: TimeInterval
    /// A localization key shown at the top (for example, that the AI could not be reached).
    var notice: String?
    /// Ask the AI for a coach's summary as soon as the screen opens (otherwise there is a button).
    var autoCoach = false
    @Binding var path: [StudyRoute]

    @Environment(AppEnvironment.self) private var environment
    @State private var coach: ExamCoachReport?
    @State private var coachLoading = false
    @State private var coachFailed = false
    @State private var flaggedCount: Int?

    private var percent: Int { ExamScoring.percent(records) }
    private var missed: [ExamAnswerRecord] { records.filter { !$0.isCorrect } }
    private var correctCount: Int { records.filter(\.isCorrect).count }

    /// The words that were missed, once each.
    private var missedWordIDs: [UUID] {
        var seen = Set<UUID>()
        return missed.flatMap(\.words).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let notice { Text(LocalizedStringKey(notice)).font(.footnote).foregroundStyle(Theme.inkSecondary) }
                scoreCard
                skillsCard
                if !missed.isEmpty {
                    coachCard
                    missedCard
                    actions
                }
                if missed.isEmpty {
                    Button { path.removeAll() } label: { Text("Done") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("examDoneButton")
                } else {
                    Button { path.removeAll() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassAction)
                        .accessibilityIdentifier("examDoneButton")
                }
            }
            .padding(Theme.Spacing.md)
        }
        .task {
            if autoCoach, coach == nil, !missed.isEmpty { await loadCoach() }
        }
    }

    // MARK: - Cards

    private var scoreCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            StudyProgressRing(fraction: Double(percent) / 100, label: percent)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(headline).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("examScoreHeadline")
                Text("\(correctCount) of \(records.count) right")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Text(durationText).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("examScoreCard")
    }

    private var headline: LocalizedStringKey {
        switch percent {
        case 90...: return "Excellent!"
        case 70..<90: return "Well done"
        case 50..<70: return "Getting there"
        default: return "Keep practicing"
        }
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = duration >= 60 ? [.minute, .second] : [.second]
        return formatter.string(from: max(1, duration)) ?? ""
    }

    @ViewBuilder
    private var skillsCard: some View {
        let skills = ExamScoring.bySkill(records)
        if skills.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("By skill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                ForEach(Array(skills.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(LocalizedStringKey(entry.skill.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(verbatim: "\(Int((entry.fraction * 100).rounded()))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        StudyProgressTrack(fraction: entry.fraction)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    @ViewBuilder
    private var coachCard: some View {
        if coachLoading || coach != nil || coachFailed || environment.examAI() != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Coach", systemImage: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentDeep)
                if coachLoading {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Looking at your mistakes…").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                } else if let coach {
                    if !coach.summary.isEmpty { Text(verbatim: coach.summary).font(.subheadline).foregroundStyle(Theme.ink) }
                    ForEach(Array(coach.tips.enumerated()), id: \.offset) { _, tip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: tip.word).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                            Text(verbatim: tip.tip).font(.footnote).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if !coach.focus.isEmpty {
                        Text(verbatim: coach.focus).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentDeep)
                    }
                } else {
                    if coachFailed {
                        Text("AI couldn't be reached.").font(.footnote).foregroundStyle(Theme.error)
                    }
                    Button { Task { await loadCoach() } } label: {
                        Label("Get tips from AI", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassAction)
                    .accessibilityIdentifier("examCoachButton")
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: Theme.accentSoft)
            .accessibilityIdentifier("examCoachCard")
        }
    }

    private var missedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("To review").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            ForEach(missed) { record in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: record.headword).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        if let kind = record.kind {
                            Text(LocalizedStringKey(kind.skill.title)).font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if !record.given.isEmpty, record.kind != .matchPairs {
                        Text(verbatim: "✗ \(record.given)").font(.footnote).foregroundStyle(Theme.error)
                    }
                    if !record.expected.isEmpty, record.kind != .matchPairs {
                        Text(verbatim: "✓ \(record.expected)").font(.footnote).foregroundStyle(Theme.success)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("examMissedRow")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button { practiceMissed() } label: {
                Label("Practice the Missed Words", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("practiceMissedButton")
            Button { flaggedCount = environment.flagExamMisses(records) } label: {
                Label("Add Them to Need Review", systemImage: "flag").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassAction)
            .disabled(flaggedCount != nil)
            .accessibilityIdentifier("flagMissedButton")
            if let flaggedCount {
                Text("\(flaggedCount) words added to Need Review.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityIdentifier("flaggedLabel")
            }
        }
    }

    // MARK: - Actions

    private func practiceMissed() {
        var retry = config
        retry.source = .words(missedWordIDs)
        retry.questionCount = min(max(missedWordIDs.count, 1), 30)
        path.append(.exam(retry))
    }

    private func loadCoach() async {
        guard !coachLoading, let ai = environment.examAI() else {
            coachFailed = environment.examAI() == nil
            return
        }
        coachLoading = true
        coachFailed = false
        let outcome = await ai.coach(records: records, percent: percent)
        coachLoading = false
        switch outcome {
        case .success(let report): coach = report
        case .failure: coachFailed = true
        }
    }
}
