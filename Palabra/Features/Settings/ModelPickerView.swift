import SwiftUI

struct ModelPickerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if environment.catalogue.models.isEmpty {
                    emptyOrLoadingContent
                } else {
                    ForEach(environment.catalogue.models) { model in
                        Button {
                            environment.selectedModelID = model.id
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
                                if model.id == environment.selectedModelID {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    if let selected = environment.selectedModelID, !environment.catalogue.models.contains(where: { $0.id == selected }) {
                        Label("Your selected model is no longer available.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .navigationTitle("Choose a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var emptyOrLoadingContent: some View {
        switch environment.catalogue.status {
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
        await environment.catalogue.refresh(apiKey: apiKey, using: environment.ai)
    }
}
