import XCTest
@testable import Palabra

@MainActor
final class SolvePhotoStorageTests: XCTestCase {
    private var store: SolveImageStore!
    private var repository: SwiftDataSolveRepository!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = .temporary()
        repository = SwiftDataSolveRepository.inMemory(images: store)
    }

    override func tearDown() { store.removeAll() }

    private func result(_ query: String = "Photo problem") -> SolveResult {
        SolveResult(query: query, pods: [SolvePod(id: "Result", title: "Result", primary: true, subpods: [SolveSubpod(plaintext: "4")])], source: .gemini, fromPhoto: true)
    }

    func testThePhotoIsKeptBesideTheAnswer() throws {
        let image = Data([9, 8, 7])
        let entry = repository.save(query: "q", key: "photo:1", result: result(), image: image, now: now)
        XCTAssertEqual(repository.problemImage(id: entry.id), image)
        XCTAssertEqual(entry.result?.fromPhoto, true)
    }

    func testSavingAgainWithoutAPhotoKeepsTheOne() {
        let first = repository.save(query: "q", key: "k", result: result(), image: Data([1]), now: now)
        _ = repository.save(query: "q", key: "k", result: result(), now: now.addingTimeInterval(5))
        XCTAssertEqual(repository.problemImage(id: first.id), Data([1]))
    }

    func testDeletingAnAnswerRemovesItsPhoto() {
        let entry = repository.save(query: "q", key: "k", result: result(), image: Data([1]), now: now)
        let id = entry.id
        repository.delete(id: id)
        XCTAssertNil(repository.problemImage(id: id))
        XCTAssertFalse(store.exists(for: id))
    }

    func testDeleteAllRemovesEveryPhoto() {
        let a = repository.save(query: "a", key: "a", result: result(), image: Data([1]), now: now)
        let b = repository.save(query: "b", key: "b", result: result(), image: Data([2]), now: now)
        repository.deleteAll()
        XCTAssertNil(repository.problemImage(id: a.id))
        XCTAssertNil(repository.problemImage(id: b.id))
    }

    func testTrimmingOldAnswersRemovesTheirPhotos() {
        var firstID: UUID?
        for index in 0..<(SwiftDataSolveRepository.maxEntries + 2) {
            let entry = repository.save(query: "q\(index)", key: "q\(index)", result: result(), image: Data([1]), now: now.addingTimeInterval(Double(index)))
            if index == 0 { firstID = entry.id }
        }
        XCTAssertNil(repository.problemImage(id: try! XCTUnwrap(firstID)))
    }

    func testThePhotoKeyIsStablePerPictureAndDiffersBetweenPictures() {
        XCTAssertEqual(SolveImageStore.key(forPhoto: Data([1, 2])), SolveImageStore.key(forPhoto: Data([1, 2])))
        XCTAssertNotEqual(SolveImageStore.key(forPhoto: Data([1, 2])), SolveImageStore.key(forPhoto: Data([1, 3])))
        XCTAssertTrue(SolveImageStore.key(forPhoto: Data([1])).hasPrefix("photo:"))
    }

    func testResultsSavedBeforePhotosExistedStillDecode() throws {
        let old = Data(#"{"query":"x","pods":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(SolveResult.self, from: old)
        XCTAssertNil(decoded.fromPhoto)
    }
}
