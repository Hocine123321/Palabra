import Foundation

/// Chooses the initial model selection from an already-filtered, newest-first
/// catalogue: a non-"lite" "flash" model, preferring one that isn't a
/// preview/experimental build, else the first model in the list.
enum DefaultModelPicker {
    static func pick(from models: [AIModel]) -> AIModel? {
        guard !models.isEmpty else { return nil }
        let flashCandidates = models.filter {
            $0.id.localizedCaseInsensitiveContains("flash") && !$0.id.localizedCaseInsensitiveContains("lite")
        }
        let pool = flashCandidates.isEmpty ? models : flashCandidates
        let stable = pool.filter {
            !$0.id.localizedCaseInsensitiveContains("preview") && !$0.id.localizedCaseInsensitiveContains("exp")
        }
        return (stable.isEmpty ? pool : stable).first
    }
}
