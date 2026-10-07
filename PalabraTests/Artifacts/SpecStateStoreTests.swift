import XCTest
@testable import Palabra

@MainActor
final class SpecStateStoreTests: XCTestCase {
    private var repo: SwiftDataArtifactRepository!
    private var artifactID: UUID!

    override func setUp() {
        repo = SwiftDataArtifactRepository.inMemory()
        guard case .success(let artifact) = repo.create(title: "T", kind: .spec, payload: Data("{}".utf8), requested: [], prompt: "p", now: Date(timeIntervalSince1970: 1_000_000)) else {
            return XCTFail("create failed")
        }
        artifactID = artifact.id
    }

    func testChecklistStateRoundTripInMemory() {
        let store = InMemorySpecStateStore()
        XCTAssertEqual(store.completed(blockID: "c1"), [])
        store.setCompleted(blockID: "c1", [0, 2])
        XCTAssertEqual(store.completed(blockID: "c1"), [0, 2])
        XCTAssertEqual(store.completed(blockID: "other"), [])
    }

    func testChecklistStatePersistsInRepository() {
        let first = ArtifactSpecStateStore(artifactID: artifactID, repository: repo)
        first.setCompleted(blockID: "c1", [1, 3])
        let second = ArtifactSpecStateStore(artifactID: artifactID, repository: repo)
        XCTAssertEqual(second.completed(blockID: "c1"), [1, 3])
        second.setCompleted(blockID: "c1", [])
        XCTAssertEqual(first.completed(blockID: "c1"), [])
    }

    func testStateIsStoredUnderSpecKey() {
        ArtifactSpecStateStore(artifactID: artifactID, repository: repo).setCompleted(blockID: "r1", [0])
        XCTAssertNotNil(repo.stateValue(artifactID: artifactID, key: "spec.r1"))
    }

    func testChecklistStateOverflowIsIgnoredNotCrashing() {
        // Fill the artifact's state budget first, then try to tick something.
        _ = repo.setStateValue(artifactID: artifactID, key: "big", value: Data(count: ArtifactLimits.maxStateBytes))
        let store = ArtifactSpecStateStore(artifactID: artifactID, repository: repo)
        store.setCompleted(blockID: "c1", [0, 1, 2])
        XCTAssertEqual(store.completed(blockID: "c1"), [])
    }

    func testCorruptStoredValueReadsAsEmpty() {
        _ = repo.setStateValue(artifactID: artifactID, key: "spec.c1", value: Data("not json".utf8))
        XCTAssertEqual(ArtifactSpecStateStore(artifactID: artifactID, repository: repo).completed(blockID: "c1"), [])
    }

    func testGrantHelperIsRequestsIntersectKnownReads() {
        let registry = CapabilityRegistry([makeCapability("library.words", .read), makeCapability("review.flag", .write)])
        XCTAssertEqual(SpecRendererView.grant(requests: ["library.words", "review.flag", "nope"], registry: registry), ["library.words"])
    }
}
