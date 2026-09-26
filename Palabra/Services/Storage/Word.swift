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
