import SwiftUI

/// Lists models from a `ModelCatalogue` and lets the person pick one,
/// writing the choice into `selection`. Shared by the "Choose a Model" (text
/// generation) and "Choose a Pronunciation Model" (TTS) screens in
/// Settings — they differ only in which catalogue and which stored
/// selection they point at.
struct ModelPickerView: View {
    let title: LocalizedStringKey
    let catalogue: ModelCatalogue
    @Binding var selection: String?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if catalogue.models.isEmpty {
                    emptyOrLoadingContent
                } else {
                    ForEach(catalogue.models) { model in
                        Button {
                            selection = model.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.displayName).foregroundStyle(Theme.ink)
                                    if let description = model.description {
                                        Text(description).font(.footnote).foregroundStyle(Theme.inkSecondary)
                                    }
                                }
                                Spacer()
                                if model.id == selection {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    if let selected = selection, !catalogue.models.contains(where: { $0.id == selected }) {
                        Label("Your selected model is no longer available.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var emptyOrLoadingContent: some View {
        switch catalogue.status {
        case .loading:
            ProgressView("Loading models…")
        case .failed(let error, _):
            ErrorBanner(message: LocalizedStringKey(error.userMessage), retryTitle: "Retry", onRetry: { Task { await refresh() } })
        default:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("No models yet.")
                Button("Fetch Models") { Task { await refresh() } }
            }
        }
    }

    private func refresh() async {
        guard let apiKey = environment.apiKey else { return }
        await catalogue.refresh(apiKey: apiKey, using: environment.ai)
    }
}
