import SwiftUI

/// The "Re-organize Library" flow: explains what will happen, lets the user
/// choose the scope, shows progress, and reports the result.
struct OrganizeLibrarySheet: View {
    let wordCount: Int
    let unorganizedCount: Int
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var scope: LibraryOrganizer.Scope = .all

    private var organizer: LibraryOrganizer { environment.organizer }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch organizer.phase {
                    case .idle:
                        intro
                    case .running(let done, let total):
                        progress(done: done, total: total)
                    case .finished(let organized, let sections):
                        finished(organized: organized, sections: sections)
                    case .failed(let error):
                        ErrorBanner(
                            message: LocalizedStringKey(error.userMessage),
                            retryTitle: error.isRetryable ? "Retry" : nil,
                            onRetry: error.isRetryable ? { organizer.start(scope: scope, environment: environment) } : nil,
                            secondaryTitle: "Close",
                            onSecondary: { organizer.dismissResult(); dismiss() }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.background)
            .navigationTitle("Re-organize Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(organizer.isRunning ? "Stop" : "Close") {
                        if organizer.isRunning { organizer.cancel() }
                        organizer.dismissResult()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(organizer.isRunning)
        .onAppear {
            organizer.dismissResult()
            scope = unorganizedCount > 0 && unorganizedCount < wordCount ? .unorganizedOnly : .all
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("The AI will read your words, group them into sections, and give each one a few tags. Your words and their content are never changed.")
                .foregroundStyle(Theme.ink)

            GlassSurface {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("What to organize").font(.headline).foregroundStyle(Theme.ink)
                    Picker("Scope", selection: $scope) {
                        Text("All \(wordCount) words").tag(LibraryOrganizer.Scope.all)
                        if unorganizedCount > 0 {
                            Text("Only \(unorganizedCount) not organized yet").tag(LibraryOrganizer.Scope.unorganizedOnly)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .padding(Theme.Spacing.md)
            }

            Text("This uses your Google AI key. About \(estimatedCalls) request(s) will be made.")
                .font(.footnote).foregroundStyle(Theme.inkSecondary)

            NavigationLink {
                OrganizationSettingsView()
            } label: {
                Label("Organization Settings", systemImage: "slider.horizontal.3")
            }

            Button {
                organizer.start(scope: scope, environment: environment)
            } label: {
                Text("Organize Now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(!environment.hasAPIKey || environment.selectedModel == nil)
            .accessibilityIdentifier("organizeNowButton")

            if !environment.hasAPIKey || environment.selectedModel == nil {
                Text("Add your API key and choose a model in Settings first.")
                    .font(.footnote).foregroundStyle(Theme.error)
            }
        }
    }

    private var estimatedCalls: Int {
        let n = scope == .all ? wordCount : unorganizedCount
        return max(1, Int((Double(n) / Double(LibraryOrganizer.batchSize)).rounded(.up)))
    }

    private func progress(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Theme.accent)
            Text("Organizing… \(done) of \(total)")
                .foregroundStyle(Theme.ink)
            Text("Nothing changes in your library until this finishes.")
                .font(.footnote).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func finished(organized: Int, sections: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(Theme.Font.serif(22)).foregroundStyle(Theme.accent)
            Text("Organized \(organized) words into \(sections) sections.")
                .foregroundStyle(Theme.ink)
            Button("Close") { organizer.dismissResult(); dismiss() }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }
}
