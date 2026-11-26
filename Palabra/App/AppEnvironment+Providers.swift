import Foundation

extension AppEnvironment {
    /// Makes `provider` the one that answers. If it already has a key, its model list is loaded and a model is chosen when
    /// none is, so the app works at once instead of asking for a trip to the model picker.
    /// Reloads a model list with the key of the provider it belongs to. The plain client is used for a list that is not the
    /// active provider's, because the retry layer's backup key belongs to the active one.
    func refresh(_ list: ModelCatalogue) async {
        guard let key = apiKey(for: list.provider) else { return }
        await list.refresh(apiKey: key, using: list.provider == activeProvider ? ai : rawAI)
    }

    func useProvider(_ provider: AIProvider) async {
        activeProvider = provider
        guard let key = apiKey else { return }
        if catalogue.models.isEmpty { await catalogue.refresh(apiKey: key, using: ai) }
        if selectedModel == nil, let pick = DefaultModelPicker.pick(from: catalogue.models) { selectedModelID = pick.id }
    }
}
