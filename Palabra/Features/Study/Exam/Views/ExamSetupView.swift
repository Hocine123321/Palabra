import SwiftUI

/// Chooses what an exam covers: which words, how many questions, which skills, and whether AI helps.
struct ExamSetupView: View {
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var config = ExamConfig()
    @State private var words: [ExamWord] = []
    @State private var loaded = false

    private struct Count {
        let name: String
        let count: Int
    }

    private var sections: [Count] {
        Dictionary(grouping: words.compactMap(\.category), by: { $0 }).map { Count(name: $0.key, count: $0.value.count) }.sorted { $0.name < $1.name }
    }

    private var tags: [Count] {
        var counts: [String: Int] = [:]
        for word in words { for tag in Set(word.tags.map { $0.lowercased() }) { counts[tag, default: 0] += 1 } }
        return counts.map { Count(name: $0.key, count: $0.value) }.sorted { $0.name < $1.name }
    }

    private var needReviewCount: Int { words.filter(\.needsReview).count }

    /// How many words the current source covers.
    private var sourceCount: Int {
        switch config.source {
        case .all, .weakest, .recent: return words.count
        case .needReview: return needReviewCount
        case .section(let name): return words.filter { $0.category == name }.count
        case .tag(let tag): return words.filter { word in word.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }.count
        case .words(let ids): return ids.count
        }
    }

    private var canStart: Bool { sourceCount > 0 && !config.kinds.isEmpty }
    private var aiAvailable: Bool { environment.hasAPIKey && environment.selectedModel != nil }
    private var speechAvailable: Bool { environment.speech.isAvailable }

    var body: some View {
        ZStack {
            ScreenBackdrop(style: .rich)
            if loaded && words.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "text.book.closed",
                        title: "No words to test yet",
                        message: "Add words to your library, then come back for an exam."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        wordsCard
                        countCard
                        skillsCard
                        aiCard
                        startButton
                        historyButton
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Exam")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            words = environment.examWords()
            loaded = true
            // A section or tag that no longer exists falls back to every word.
            if case .section(let name) = config.source, !sections.contains(where: { $0.name == name }) { config.source = .all }
            if case .tag(let tag) = config.source, !tags.contains(where: { $0.name == tag }) { config.source = .all }
            if !aiAvailable { config.useAI = false }
        }
    }

    // MARK: - Cards

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var wordsCard: some View {
        card("Words") {
            Picker("Words", selection: $config.source) {
                Text("All words").tag(ExamSource.all)
                Text("Weakest first").tag(ExamSource.weakest)
                Text("Recently added").tag(ExamSource.recent)
                if needReviewCount > 0 { Text("Need Review").tag(ExamSource.needReview) }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Text(verbatim: "\(section.name) (\(section.count))").tag(ExamSource.section(section.name))
                }
                ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                    Text(verbatim: "#\(tag.name) (\(tag.count))").tag(ExamSource.tag(tag.name))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.accentDeep)
            .accessibilityIdentifier("examSourcePicker")
            Text("\(sourceCount) words in this exam's pool")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            if words.count < 4 {
                Text("With fewer than 4 words some question types are skipped.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var countCard: some View {
        card("Questions") {
            Picker("Questions", selection: $config.questionCount) {
                ForEach(ExamConfig.questionCounts, id: \.self) { count in
                    Text(verbatim: "\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("examCountPicker")
        }
    }

    private var skillsCard: some View {
        card("Skills") {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(ExamSkill.allCases) { skill in skillRow(skill) }
            }
        }
    }

    private func skillRow(_ skill: ExamSkill) -> some View {
        let unavailable = (skill == .speaking && !speechAvailable) || (skill.needsAI && !config.useAI)
        let on = config.skills.contains(skill) && !unavailable
        return Button {
            if config.skills.contains(skill) { config.skills.remove(skill) } else { config.skills.insert(skill) }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemImage: skill.systemImage, tint: on ? Theme.accent : Theme.fill, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(skill.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(LocalizedStringKey(skill.detail)).font(.caption).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                    if unavailable {
                        Text(skill == .speaking ? LocalizedStringKey("Not available on this device.") : LocalizedStringKey("Turn on AI to use this."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentDeep)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Theme.inkSecondary)
            }
            .contentShape(Rectangle())
            .opacity(unavailable ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("examSkill-\(skill.rawValue)")
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle(isOn: $config.useAI) {
                Label("Use AI", systemImage: "sparkles").font(.subheadline.weight(.semibold))
            }
            .tint(Theme.accent)
            .disabled(!aiAvailable)
            .accessibilityIdentifier("examAIToggle")
            Text(aiAvailable
                 ? LocalizedStringKey("Fresh example sentences, written answers checked for you, and tips on your mistakes at the end. Uses your Gemini key. Everything else works without it.")
                 : LocalizedStringKey("Add a Gemini key in Settings to turn this on. The exam works fully without it."))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var startButton: some View {
        Button { path.append(.exam(config)) } label: {
            Label("Start Exam", systemImage: "play.fill")
        }
        .buttonStyle(.primary)
        .disabled(!canStart)
        .accessibilityIdentifier("startExamButton")
    }

    private var historyButton: some View {
        Button { path.append(.examHistory) } label: {
            Label("Past Exams", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassAction)
        .accessibilityIdentifier("examHistoryButton")
    }
}
