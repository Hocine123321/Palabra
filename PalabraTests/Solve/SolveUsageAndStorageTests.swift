import XCTest
@testable import Palabra

final class SolveUsageTests: XCTestCase {
    private func usage() -> SolveUsage { SolveUsage(defaults: UserDefaults(suiteName: "usage-\(UUID().uuidString)")!) }
    private let october = Date(timeIntervalSince1970: 1_791_644_400) // 2026-10-10
    private let november = Date(timeIntervalSince1970: 1_793_800_000) // 2026-11-04

    func testCountsCallsWithinAMonthAndResetsInTheNext() {
        let usage = usage()
        XCTAssertEqual(usage.count(now: october), 0)
        usage.record(now: october)
        usage.record(now: october)
        XCTAssertEqual(usage.count(now: october), 2)
        XCTAssertEqual(usage.count(now: november), 0)
        usage.record(now: november)
        XCTAssertEqual(usage.count(now: november), 1)
        XCTAssertEqual(usage.count(now: october), 0, "the old month is replaced")
    }

    func testMonthKeyIsUTC() {
        XCTAssertEqual(SolveUsage.month(of: october), "2026-10")
        XCTAssertEqual(SolveUsage.month(of: Date(timeIntervalSince1970: 1_790_812_800 - 1)), "2026-09")
    }
}

@MainActor
final class SolveRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var repository: SwiftDataSolveRepository!

    override func setUp() {
        repository = SwiftDataSolveRepository.inMemory()
    }

    func testSaveAndFindByKeyAndID() {
        let entry = repository.save(query: "x^2-4=0", key: "x^2-4=0", result: .sample(), now: now)
        XCTAssertEqual(repository.entry(id: entry.id)?.query, "x^2-4=0")
        XCTAssertEqual(repository.entry(forKey: "x^2-4=0")?.id, entry.id)
        XCTAssertEqual(repository.entry(id: entry.id)?.result, .sample())
        XCTAssertNil(repository.entry(forKey: "nope"))
    }

    func testSavingTheSameKeyReplacesAndBumpsTheEntry() {
        let first = repository.save(query: "a", key: "a", result: .sample(query: "a"), now: now)
        repository.save(query: "b", key: "b", result: .sample(query: "b"), now: now.addingTimeInterval(10))
        let again = repository.save(query: "a", key: "a", result: .sample(query: "a", withStepsOffer: false), now: now.addingTimeInterval(20))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(repository.entries(limit: 10).map(\.queryKey), ["a", "b"])
        XCTAssertNil(repository.entry(id: first.id)?.result?.pods[1].stepsInput)
    }

    func testUpdateKeepsTheOrder() {
        let a = repository.save(query: "a", key: "a", result: .sample(query: "a"), now: now)
        repository.save(query: "b", key: "b", result: .sample(query: "b"), now: now.addingTimeInterval(10))
        repository.update(id: a.id, result: .sample(query: "a", withStepsOffer: false), now: now.addingTimeInterval(20))
        XCTAssertEqual(repository.entries(limit: 10).map(\.queryKey), ["b", "a"])
        XCTAssertNil(repository.entry(id: a.id)?.result?.pods[1].stepsInput)
    }

    func testLimitDeleteAndDeleteAll() {
        for i in 0..<5 { repository.save(query: "q\(i)", key: "q\(i)", result: .sample(query: "q\(i)"), now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(repository.entries(limit: 3).map(\.queryKey), ["q4", "q3", "q2"])
        let id = repository.entry(forKey: "q0")!.id
        repository.delete(id: id)
        XCTAssertNil(repository.entry(id: id))
        repository.deleteAll()
        XCTAssertTrue(repository.entries(limit: 10).isEmpty)
    }

    func testOldestEntriesBeyondTheCapAreDropped() {
        for i in 0..<(SwiftDataSolveRepository.maxEntries + 3) {
            repository.save(query: "q\(i)", key: "q\(i)", result: .sample(query: "q\(i)"), now: now.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(repository.entries(limit: Int.max).count, SwiftDataSolveRepository.maxEntries)
        XCTAssertNil(repository.entry(forKey: "q0"))
        XCTAssertNotNil(repository.entry(forKey: "q\(SwiftDataSolveRepository.maxEntries + 2)"))
    }
}

final class SolveModelsCodingTests: XCTestCase {
    func testResultRoundTripsWithImagesAndOldDataStillDecodes() throws {
        var result = SolveResult.sample()
        result.pods[1].subpods[0].imageData = Data([1, 2, 3])
        result.pods[1].subpods[0].imageWidth = 40
        XCTAssertEqual(try JSONDecoder().decode(SolveResult.self, from: JSONEncoder().encode(result)), result)

        let old = try JSONDecoder().decode(SolveResult.self, from: Data(#"{"query":"q","pods":[{"id":"Result","title":"R"}]}"#.utf8))
        XCTAssertEqual(old.query, "q")
        XCTAssertEqual(old.pods[0].subpods, [])
        XCTAssertFalse(old.pods[0].primary)
        XCTAssertEqual(try JSONDecoder().decode(SolveResult.self, from: Data("{}".utf8)).pods, [])
    }

    func testAnswerPodFallsBackToTheFirstNonInputPod() {
        let result = SolveResult(query: "q", pods: [SolvePod(id: "Input", title: "I"), SolvePod(id: "Solution", title: "S"), SolvePod(id: "Plot", title: "P")])
        XCTAssertEqual(result.answerPod?.id, "Solution")
        XCTAssertEqual(result.otherPods.map(\.id), ["Plot"])
    }

    func testWebURLEncodesTheQuery() {
        XCTAssertEqual(SolveResult(query: "x+1=2 & y").webURL?.absoluteString, "https://www.wolframalpha.com/input?i=x+1%3D2%20%26%20y")
    }

    func testReplacingSwapsThePodByID() {
        let richer = SolvePod(id: "Result", title: "Result", hasSteps: true)
        let updated = SolveResult.sample().replacing(richer)
        XCTAssertTrue(updated.pods[1].hasSteps)
        XCTAssertEqual(updated.pods.count, 3)
    }
}
