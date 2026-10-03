import Foundation

/// Writes AI-generated word content into the library, the same way whether
/// it came from an interactive `AddWordFlow.save()` or from
/// `WordQueueProcessor` finishing a queued request while the person was
/// doing something else: insert-or-replace, then kick off pronunciation and
/// organization for the saved word.
enum WordWriter {
    @discardableResult
    @MainActor
    static func commit(content: WordContent, mode: AddWordFlow.Mode, environment: AppEnvironment) -> Word? {
        let key = WordKey.identity(content.word)
        let searchKey = WordKey.search(content.word)
        let rawData = (try? JSONEncoder().encode(content)) ?? Data()
        switch mode {
        case .new:
            // Guard a race: another save could have claimed this key in the meantime.
            if let existing = environment.repository.find(key: key) {
                environment.repository.replaceContent(id: existing.id, content: content, rawJSON: rawData)
            } else {
                environment.repository.insert(spanish: content.word, key: key, searchKey: searchKey, content: content, rawJSON: rawData)
            }
        case .regenerate(let existingID, _):
            environment.repository.replaceContent(id: existingID, content: content, rawJSON: rawData)
        }
        // On regenerate the headword may have been corrected, so the new key can differ
        // from the stored one: find the word by id there, by key for a new word.
        let saved: Word?
        if case .regenerate(let existingID, _) = mode {
            saved = environment.repository.allWords().first { $0.id == existingID }
        } else {
            saved = environment.repository.find(key: key)
        }
        if let saved {
            environment.requestPronunciationIfConfigured(for: saved)
            // A regenerated word keeps its existing section and tags.
            if saved.category == nil { environment.requestOrganizationIfConfigured(for: saved) }
        }
        return saved
    }
}
