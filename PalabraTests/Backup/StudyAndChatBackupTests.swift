import XCTest
@testable import Palabra

@MainActor
final class StudyBackupTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func studiedDeck(_ repo: SwiftDataCardRepository) -> (deck: Deck, card: Card) {
        let deck = repo.createDeck(name: "Trip", drafts: [CardDraft(front: "gato", back: "cat")], now: t0)
        let card = repo.cards(inDeck: deck.id)[0]
        repo.record(cardID: card.id, grade: .easy, now: t0)
        return (deck, card)
    }

    func testBackupHoldsUserDecksStudiedVocabularyAndTheirHistory() {
        let repo = SwiftDataCardRepository.inMemory()
        let word = UUID()
        let other = UUID()
        repo.syncVocabulary([VocabularyCardEntry(wordID: word, front: "hablar", back: "to speak"), VocabularyCardEntry(wordID: other, front: "comer", back: "to eat")])
        let vocabulary = repo.decks().first { $0.kind == .vocabulary }!
        let studied = repo.cards(inDeck: vocabulary.id).first { $0.sourceWordID == word }!
        repo.record(cardID: studied.id, grade: .good, now: t0)
        _ = studiedDeck(repo)

        let backup = repo.backup()
        XCTAssertEqual(backup.decks.map(\.name), ["Trip"])
        XCTAssertEqual(backup.cards.count, 1)
        XCTAssertEqual(backup.vocabulary.map(\.wordID), [word], "only studied vocabulary cards are listed")
        XCTAssertEqual(backup.logs.count, 2)
    }

    func testRestoreRebuildsDecksCardsProgressAndHistoryOnce() throws {
        let source = SwiftDataCardRepository.inMemory()
        let (_, card) = studiedDeck(source)
        let backup = source.backup()

        let target = SwiftDataCardRepository.inMemory()
        let first = try target.restore(backup, wordIDMap: [:])
        XCTAssertEqual(first.decks, 1)
        XCTAssertEqual(first.cards, 1)
        let logs = try target.restoreLogs(backup.logs, cardIDMap: first.cardIDMap)
        XCTAssertEqual(logs, 1)
        let restored = try XCTUnwrap(target.decks().first { $0.kind == .user })
        let restoredCard = try XCTUnwrap(target.cards(inDeck: restored.id).first)
        XCTAssertEqual(restoredCard.id, card.id)
        XCTAssertEqual(restoredCard.srs, card.srs)

        let second = try target.restore(backup, wordIDMap: [:])
        XCTAssertEqual(second.decks, 0)
        XCTAssertEqual(second.cards, 0)
        XCTAssertEqual(try target.restoreLogs(backup.logs, cardIDMap: second.cardIDMap), 0)
        XCTAssertEqual(target.cards(inDeck: restored.id).count, 1)
    }

    func testRestoreMergesIntoADeckWithTheSameNameAndKeepsExistingProgress() throws {
        let source = SwiftDataCardRepository.inMemory()
        _ = studiedDeck(source)
        let backup = source.backup()

        let target = SwiftDataCardRepository.inMemory()
        let deck = target.createDeck(name: "trip", drafts: [CardDraft(front: "Gato", back: "Cat")], now: t0)
        let own = target.cards(inDeck: deck.id)[0]
        let result = try target.restore(backup, wordIDMap: [:])
        XCTAssertEqual(result.decks, 0)
        XCTAssertEqual(result.cards, 0)
        XCTAssertEqual(result.progress, 1, "the existing card was still new, so it takes the backup's progress")
        XCTAssertEqual(target.cards(inDeck: deck.id).count, 1)
        XCTAssertNotEqual(target.cards(inDeck: deck.id)[0].phase, .new)
        XCTAssertEqual(target.decks().filter { $0.kind == .user }.count, 1)
        _ = own
    }

    func testVocabularyProgressFollowsTheWordToItsNewID() throws {
        let source = SwiftDataCardRepository.inMemory()
        let oldID = UUID()
        source.syncVocabulary([VocabularyCardEntry(wordID: oldID, front: "hablar", back: "to speak")])
        let card = source.cards(inDeck: source.decks()[0].id)[0]
        source.record(cardID: card.id, grade: .good, now: t0)
        let backup = source.backup()

        let target = SwiftDataCardRepository.inMemory()
        let newID = UUID()
        target.syncVocabulary([VocabularyCardEntry(wordID: newID, front: "hablar", back: "to speak")])
        let result = try target.restore(backup, wordIDMap: [oldID: newID])
        XCTAssertEqual(result.progress, 1)
        let restored = target.cards(inDeck: target.decks()[0].id)[0]
        XCTAssertEqual(restored.srs, source.cards(inDeck: source.decks()[0].id)[0].srs)
    }

    func testDamagedSRSValuesAreKeptInRange() {
        let state = StudyBackup.SRS(phase: "bogus", interval: .nan, ease: 99, reps: -4, lapses: -1, due: t0).state
        XCTAssertEqual(state.phase, .new)
        XCTAssertEqual(state.interval, 0)
        XCTAssertEqual(state.ease, SRSScheduler.maxEase)
        XCTAssertEqual(state.reps, 0)
        XCTAssertEqual(state.lapses, 0)
    }

    func testHistoryForUnknownCardsIsIgnored() throws {
        let repo = SwiftDataCardRepository.inMemory()
        let log = StudyBackup.LogRecord(id: UUID(), cardID: UUID(), grade: 2, reviewedAt: t0, prevInterval: 0, newInterval: 1)
        XCTAssertEqual(try repo.restoreLogs([log], cardIDMap: [:]), 0)
    }
}

@MainActor
final class ChatBackupTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testBackupAndRestoreKeepTurnsTitleAndDates() throws {
        let source = SwiftDataChatRepository.inMemory()
        let word = UUID()
        source.create(title: "About hablar", wordID: word, turns: [ChatTurn(role: .user, text: "hola"), ChatTurn(role: .assistant, text: "¡Hola!")], now: t0)
        let records = source.backupConversations()

        let target = SwiftDataChatRepository.inMemory()
        XCTAssertEqual(try target.restore(records, wordIDMap: [:]), 1)
        let restored = try XCTUnwrap(target.conversation(id: records[0].id))
        XCTAssertEqual(restored.title, "About hablar")
        XCTAssertEqual(restored.turns.map(\.text), ["hola", "¡Hola!"])
        XCTAssertEqual(restored.wordID, word)
        XCTAssertEqual(restored.createdAt, t0)
    }

    func testRestoreSkipsChatsThatAreAlreadyHereAndRepointsWords() throws {
        let source = SwiftDataChatRepository.inMemory()
        let oldWord = UUID(), newWord = UUID()
        source.create(title: "a", wordID: oldWord, turns: [], now: t0)
        let records = source.backupConversations()

        let target = SwiftDataChatRepository.inMemory()
        XCTAssertEqual(try target.restore(records, wordIDMap: [oldWord: newWord]), 1)
        XCTAssertEqual(target.conversation(forWordID: newWord)?.id, records[0].id)
        XCTAssertEqual(try target.restore(records, wordIDMap: [oldWord: newWord]), 0)
        XCTAssertEqual(target.conversations().count, 1)
    }

    func testRestoreCapsOversizedText() throws {
        let target = SwiftDataChatRepository.inMemory()
        let long = String(repeating: "x", count: ChatLimits.maxTextLength + 500)
        let record = ChatBackup(id: UUID(), title: String(repeating: "t", count: 500), wordID: nil, turns: [ChatTurn(role: .user, text: long)], createdAt: t0, updatedAt: t0)
        _ = try target.restore([record], wordIDMap: [:])
        let stored = try XCTUnwrap(target.conversation(id: record.id))
        XCTAssertEqual(stored.turns[0].text.count, ChatLimits.maxTextLength)
        XCTAssertEqual(stored.title.count, ChatLimits.maxTitleLength)
    }
}
