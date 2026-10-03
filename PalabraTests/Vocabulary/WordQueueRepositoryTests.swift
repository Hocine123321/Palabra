import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class WordQueueRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataWordQueueRepository!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        repository = SwiftDataWordQueueRepository(context: ModelContext(container))
    }

    func testEnqueueNewStoresNoExistingID() {
        let item = repository.enqueue(inputWord: "hablar", mode: .new, language: .english)
        XCTAssertEqual(item.inputWord, "hablar")
        XCTAssertEqual(item.status, .pending)
        XCTAssertEqual(item.attempts, 0)
        if case .new = item.mode {} else { XCTFail("expected .new, got \(item.mode)") }
    }

    func testEnqueueRegeneratePreservesExistingIDAndDate() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000)
        let item = repository.enqueue(inputWord: "hablar", mode: .regenerate(existingID: id, existingCreatedAt: date), language: .arabic)
        guard case .regenerate(let gotID, let gotDate) = item.mode else { return XCTFail("expected .regenerate") }
        XCTAssertEqual(gotID, id)
        XCTAssertEqual(gotDate, date)
        XCTAssertEqual(item.language, .arabic)
    }

    func testNextPendingIsOldestPendingItem() {
        let first = repository.enqueue(inputWord: "primero", mode: .new, language: .english)
        let second = repository.enqueue(inputWord: "segundo", mode: .new, language: .english)
        XCTAssertEqual(repository.nextPending()?.id, first.id)

        repository.markProcessing(id: first.id)
        XCTAssertEqual(repository.nextPending()?.id, second.id, "a processing item isn't pending")
    }

    func testMarkFailedSetsStatusAndMessage() {
        let item = repository.enqueue(inputWord: "hablar", mode: .new, language: .english)
        repository.markFailed(id: item.id, lastError: "bad key")
        let reloaded = repository.allItems().first { $0.id == item.id }
        XCTAssertEqual(reloaded?.status, .failed)
        XCTAssertEqual(reloaded?.lastErrorMessage, "bad key")
        XCTAssertNil(repository.nextPending(), "a failed item is never picked up automatically")
    }

    func testMarkPendingClearsErrorAndUpdatesAttempts() {
        let item = repository.enqueue(inputWord: "hablar", mode: .new, language: .english)
        repository.markFailed(id: item.id, lastError: "temporary")
        repository.markPending(id: item.id, attempts: 2, lastError: nil)
        let reloaded = repository.allItems().first { $0.id == item.id }
        XCTAssertEqual(reloaded?.status, .pending)
        XCTAssertEqual(reloaded?.attempts, 2)
        XCTAssertNil(reloaded?.lastErrorMessage)
    }

    func testRemoveDeletesTheItem() {
        let item = repository.enqueue(inputWord: "hablar", mode: .new, language: .english)
        repository.remove(id: item.id)
        XCTAssertTrue(repository.allItems().isEmpty)
    }
}
