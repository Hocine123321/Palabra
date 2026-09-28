import Foundation
import Observation

/// The cached, filtered list of Google AI models. Loads its disk cache once
/// at launch; `refresh` replaces the cache only on a non-empty success and
/// otherwise leaves the previous good list in place.
///
/// Shared by the text-generation model catalogue and the pronunciation (TTS)
/// model catalogue: both list the same underlying `models.list` endpoint,
/// they just keep different models from it (`ModelFilter` vs
/// `TTSModelFilter`) and cache to different files so the two selections
/// don't clobber each other.
@MainActor
@Observable
final class ModelCatalogue {
    enum Status: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(AIError, hasCache: Bool)
    }

    private(set) var models: [AIModel] = []
    private(set) var status: Status = .idle

    private let cacheURL: URL
    private let filter: ([AIModel]) -> [AIModel]

    init(
        cacheFileName: String = "ModelCatalogue.json",
        filter: @escaping ([AIModel]) -> [AIModel] = ModelFilter.apply,
        cacheDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) {
        cacheURL = cacheDirectory.appendingPathComponent(cacheFileName)
        self.filter = filter
    }

    struct Snapshot: Codable {
        var models: [AIModel]
        var fetchedAt: Date
    }

    func loadCacheIfPresent() {
        guard let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        models = snapshot.models
        status = .loaded(snapshot.fetchedAt)
    }

    func refresh(apiKey: String, using client: AIClient) async {
        status = .loading
        switch await client.listModels(apiKey: apiKey) {
        case .failure(let error):
            status = .failed(error, hasCache: !models.isEmpty)
        case .success(let raw):
            let filtered = filter(raw)
            guard !filtered.isEmpty else {
                status = .failed(.emptyCatalogue, hasCache: !models.isEmpty)
                return
            }
            models = filtered
            let now = Date()
            writeCache(Snapshot(models: filtered, fetchedAt: now))
            status = .loaded(now)
        }
    }

    private func writeCache(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
