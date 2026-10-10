import SwiftUI
import UIKit

/// A solved problem as a page: the answer first, then Wolfram|Alpha's other sections. Images are saved with the answer.
struct SolveResultView: View {
    let entryID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var model: SolveResultModel?
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
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
                problemHeader(result)
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

    private func problemHeader(_ result: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Problem").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Text(verbatim: result.query)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            if let interpretation = result.interpretation, !interpretation.isEmpty, interpretation != result.query {
                Text(verbatim: interpretation).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    // MARK: - Pods

    private func podCard(_ pod: SolvePod, hero: Bool, model: SolveResultModel, result: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(verbatim: pod.title)
                    .font(hero ? .subheadline.weight(.bold) : .footnote.weight(.semibold))
                    .foregroundStyle(hero ? Theme.accent : Theme.inkSecondary)
                Spacer()
                if hero, !pod.plainText.isEmpty {
                    Button {
                        UIPasteboard.general.string = pod.plainText
                        copied = true
                    } label: {
                        Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("copyAnswerButton")
                }
            }
            ForEach(Array(pod.subpods.enumerated()), id: \.offset) { _, sub in
                subpodView(sub)
            }
            if pod.stepsInput != nil { stepsButton(pod, model) }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay {
            if hero {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.accent.opacity(0.6), lineWidth: 1.5)
            }
        }
        .accessibilityIdentifier(hero ? "answerCard" : "podCard")
    }

    @ViewBuilder
    private func subpodView(_ sub: SolveSubpod) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !sub.title.isEmpty {
                Text(verbatim: sub.title).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            if let data = sub.imageData, let image = UIImage(data: data) {
                // Wolfram images are 2x: show them at natural size, never larger.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width / 2, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .accessibilityLabel(Text(verbatim: sub.plaintext))
            } else if !sub.plaintext.isEmpty {
                Text(verbatim: sub.plaintext)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
            }
        }
    }

    private func stepsButton(_ pod: SolvePod, _ model: SolveResultModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                Task { await model.loadSteps(podID: pod.id) }
            } label: {
                if model.loadingStepsPodID == pod.id {
                    HStack(spacing: Theme.Spacing.sm) { ProgressView(); Text("Loading steps\u{2026}") }
                } else {
                    Label("Show steps", systemImage: "list.number")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.loadingStepsPodID != nil)
            .accessibilityIdentifier("showStepsButton")
            Text("Uses one more free call.").font(.caption).foregroundStyle(Theme.inkSecondary)
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
                }
                .accessibilityIdentifier("openInWolframLink")
            }
            Text("Powered by Wolfram|Alpha").font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func shareText(_ result: SolveResult) -> String {
        let answer = result.answerText
        return answer.isEmpty ? result.query : "\(result.query)\n= \(answer)"
    }
}
