import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class PersistenceTests: XCTestCase {
    func testSaveReportsSuccessForAHealthyContext() throws {
        let container = try ModelContainer(for: Schema([Deck.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.insert(Deck(name: "A", kind: .user))
        XCTAssertTrue(Persistence.save(context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Deck>()), 1)
    }
}
