import SwiftUI
import UIKit

/// A solved problem as a page: the answer first, then the other sections. Wolfram|Alpha images are saved with the answer.
struct SolveResultView: View {
    let entryID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var model: SolveResultModel?
    @State private var copied = false
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRightToLeft: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        ZStack {
            ScreenBackdrop()
            if let model {
                if let result = model.result { page(model, result) } else {
                    EmptyStateView(systemImage: "questionmark.circle", title: "Answer not found", message: "It may have been deleted.")
                }
            }
        }
        .navigationTitle("Answer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let result = model?.result {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(result)) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                }
            }
        }
        .onAppear {
            if model == nil { model = SolveResultModel(tool: environment.solve, entryID: entryID) }
        }
    }

    private func page(_ model: SolveResultModel, _ result: SolveResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                problemHeader(result, photo: model.problemImage)
                if let answer = result.answerPod { podCard(answer, hero: true, model: model, result: result) }
                if let error = model.stepsError { stepsErrorView(error, model) }
                ForEach(Array(result.otherPods.enumerated()), id: \.offset) { _, pod in
                    podCard(pod, hero: false, model: model, result: result)
                }
                footer(result)
            }
            .padding(Theme.Spacing.md)
        }
    }

    /// A photo problem is shown as the photo itself; a typed one as its text.
    @ViewBuilder
    private func problemHeader(_ result: SolveResult, photo: Data?) -> some View {
        if result.fromPhoto == true, let photo, let image = UIImage(data: photo) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Problem").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .accessibilityLabel(Text("The photo"))
                    .accessibilityIdentifier("problemPhoto")
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Problem").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                Text(verbatim: BidiText.display(result.query, rightToLeftLayout: isRightToLeft))
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                if let interpretation = result.interpretation, !interpretation.isEmpty, interpretation != result.query {
                    Text(verbatim: BidiText.display(interpretation, rightToLeftLayout: isRightToLeft)).font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    // MARK: - Pods

    @ViewBuilder
    private func podCard(_ pod: SolvePod, hero: Bool, model: SolveResultModel, result: SolveResult) -> some View {
        if hero {
            // The answer is a sand paper cutout with ink text, like a flashcard face.
            CutoutCard(tint: Theme.tileTints[3]) {
                podContent(pod, hero: true, model: model)
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
            .accessibilityIdentifier("answerCard")
        } else {
            podContent(pod, hero: false, model: model)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                .accessibilityIdentifier("podCard")
        }
    }

    private func podContent(_ pod: SolvePod, hero: Bool, model: SolveResultModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(LocalizedStringKey(pod.title))
                    .font(hero ? Theme.Font.tile : SwiftUI.Font.footnote.weight(.semibold))
                    .foregroundStyle(hero ? Theme.onTint.opacity(0.7) : Theme.inkSecondary)
                Spacer()
                if hero, !pod.plainText.isEmpty {
                    Button {
                        UIPasteboard.general.string = pod.plainText
                        copied = true
                    } label: {
                        Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.onTint)
                            .padding(.horizontal, Theme.Spacing.sm + 4)
                            .padding(.vertical, 6)
                            .background(Theme.onTint.opacity(0.10), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: copied) { _, new in new }
                    .accessibilityIdentifier("copyAnswerButton")
                }
            }
            ForEach(Array(pod.subpods.enumerated()), id: \.offset) { _, sub in
                subpodView(sub, hero: hero)
            }
            if pod.stepsInput != nil { stepsButton(pod, model, hero: hero) }
        }
    }

    @ViewBuilder
    private func subpodView(_ sub: SolveSubpod, hero: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !sub.title.isEmpty {
                Text(LocalizedStringKey(sub.title))
                    .font(.caption)
                    .foregroundStyle(hero ? Theme.onTint.opacity(0.7) : Theme.inkSecondary)
            }
            if let data = sub.imageData, let image = UIImage(data: data) {
                // Wolfram images are 2x: show them at natural size, never larger. They are dark ink
                // drawn for a light page, so they always sit on warm paper, in dark mode too.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width / 2, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .accessibilityLabel(Text(verbatim: sub.plaintext))
            } else if !sub.plaintext.isEmpty {
                textLines(sub.plaintext, hero: hero)
            }
        }
    }

    /// The text of a part, line by line, so each line keeps its own direction: Arabic text reads right to left with its
    /// formulas intact, a formula line stays left to right, and a numbered step has its number in a column of its own.
    private func textLines(_ text: String, hero: Bool) -> some View {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if let numbered = BidiText.numberedLine(line) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(verbatim: BidiText.isolated("\(numbered.number)."))
                            .font(SwiftUI.Font.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(hero ? Theme.onTint.opacity(0.7) : Theme.inkSecondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        lineText(numbered.text, hero: hero)
                    }
                } else {
                    lineText(line, hero: hero)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineText(_ line: String, hero: Bool) -> some View {
        Text(verbatim: BidiText.display(line, rightToLeftLayout: isRightToLeft))
            // The monospaced face has no Arabic letters, so Arabic text uses the normal face.
            .font(BidiText.containsArabic(line) ? SwiftUI.Font.body : SwiftUI.Font.system(.body, design: .monospaced))
            .foregroundStyle(hero ? Theme.onTint : Theme.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func stepsButton(_ pod: SolvePod, _ model: SolveResultModel, hero: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                Task { await model.loadSteps(podID: pod.id) }
            } label: {
                Group {
                    if model.loadingStepsPodID == pod.id {
                        HStack(spacing: Theme.Spacing.sm) { ProgressView(); Text("Loading steps\u{2026}") }
                    } else {
                        Label("Show steps", systemImage: "list.number")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hero ? Theme.onTint : Theme.ink)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(hero ? Theme.onTint.opacity(0.10) : Theme.fill, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.loadingStepsPodID != nil)
            .accessibilityIdentifier("showStepsButton")
            Text(pod.stepsAreAIWritten ? LocalizedStringKey("Written by Gemini from the checked answer.") : LocalizedStringKey("Uses one more free call."))
                .font(.caption)
                .foregroundStyle(hero ? Theme.onTint.opacity(0.7) : Theme.inkSecondary)
        }
    }

    private func stepsErrorView(_ error: SolveError, _ model: SolveResultModel) -> some View {
        ErrorBanner(
            message: LocalizedStringKey(error.userMessage),
            retryTitle: nil,
            secondaryTitle: "Dismiss",
            onSecondary: { model.dismissStepsError() }
        )
    }

    // MARK: - Footer

    private func footer(_ result: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let url = result.webURL {
                Link(destination: url) {
                    Label("Open in Wolfram|Alpha", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .accessibilityIdentifier("openInWolframLink")
            }
            Text(sourceNote(result.source)).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    /// Where the answer came from. Answers saved before sources were recorded were Wolfram|Alpha's.
    private func sourceNote(_ source: SolveSource?) -> LocalizedStringKey {
        switch source {
        case .onDevice: return "Solved on your device."
        case .gemini: return "Solved by Gemini. Double-check it before you rely on it."
        case .wolfram, nil: return "Powered by Wolfram|Alpha"
        }
    }

    private func shareText(_ result: SolveResult) -> String {
        let answer = result.answerText
        return answer.isEmpty ? result.query : "\(result.query)\n= \(answer)"
    }
}
