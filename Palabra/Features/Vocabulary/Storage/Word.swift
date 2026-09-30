import Foundation
import SwiftData

/// One saved vocabulary word. `content` and `chat` are computed over the
/// stored `contentData`/`chatData` JSON so the raw AI response format can
/// change without a SwiftData migration; a decode failure falls back to
/// `WordContent.empty` / `[]` rather than crashing the UI.
@Model
final class Word {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var spanish: String
    var searchKey: String
    var contentData: Data
    var rawJSON: Data
    var translation: String
    var partOfSpeech: String
    var createdAt: Date
    var updatedAt: Date
    var chatData: Data
    /// Cached pronunciation audio (a complete WAV file) from Gemini TTS, or
    /// `nil` if it hasn't been generated yet (including for words imported
    /// from a library export, which never carry audio — see
    /// `VocabularyLibraryExporter`). Not exported/imported: it's a local cache of
    /// something regenerable, not learned content.
    var pronunciationAudio: Data?
    /// Library organization (added in 1.1). Both are optional so existing
    /// on-device libraries migrate automatically; `nil` means "not organized yet".
    var category: String?
    /// JSON-encoded `[String]`. Stored as `Data?` like the other list fields so
    /// the on-device schema stays simple.
    var tagsData: Data?

    init(spanish: String, key: String, searchKey: String, content: WordContent, rawJSON: Data, createdAt: Date = Date()) {
        id = UUID()
        self.spanish = spanish
        self.key = key
        self.searchKey = searchKey
        contentData = (try? JSONEncoder().encode(content)) ?? Data()
        self.rawJSON = rawJSON
        translation = content.meaning.translations.first ?? ""
        partOfSpeech = content.forms.partOfSpeech
        self.createdAt = createdAt
        updatedAt = createdAt
        chatData = (try? JSONEncoder().encode([ChatMessage]())) ?? Data()
        pronunciationAudio = nil
        category = nil
        tagsData = nil
    }

    var tags: [String] {
        get { tagsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { tagsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    var content: WordContent {
        get { (try? JSONDecoder().decode(WordContent.self, from: contentData)) ?? .empty }
        set {
            contentData = (try? JSONEncoder().encode(newValue)) ?? Data()
            translation = newValue.meaning.translations.first ?? ""
            partOfSpeech = newValue.forms.partOfSpeech
        }
    }

    var chat: [ChatMessage] {
        get { (try? JSONDecoder().decode([ChatMessage].self, from: chatData)) ?? [] }
        set { chatData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
