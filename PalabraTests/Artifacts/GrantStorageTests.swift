import XCTest
@testable import Palabra

@MainActor
final class GrantStorageTests: XCTestCase {
    private var repo: SwiftDataArtifactRepository!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        repo = SwiftDataArtifactRepository.inMemory()
    }

    private func makeArtifact() -> Artifact {
        guard case .success(let artifact) = repo.create(title: "T", kind: .app, payload: Data("<html></html>".utf8), requested: ["library.words"], prompt: "p", now: t0) else {
            XCTFail("create failed")
            fatalError()
        }
        return artifact
    }

    func testSetGrantedRoundTrips() {
        let artifact = makeArtifact()
        XCTAssertEqual(artifact.grantedNames, [])
        repo.setGranted(artifactID: artifact.id, names: ["library.words"])
        XCTAssertEqual(repo.artifact(id: artifact.id)?.grantedNames, ["library.words"])
    }

    func testSetGrantedSortsAndDedupes() {
        let artifact = makeArtifact()
        repo.setGranted(artifactID: artifact.id, names: ["storage.get", "ai.generate", "storage.get"])
        XCTAssertEqual(repo.artifact(id: artifact.id)?.grantedNames, ["ai.generate", "storage.get"])
    }

    func testSetGrantedUnknownIDIsNoOp() {
        repo.setGranted(artifactID: UUID(), names: ["library.words"])
        XCTAssertTrue(repo.artifacts().isEmpty)
    }

    func testGrantSurvivesAddVersionAndRestore() {
        let artifact = makeArtifact()
        repo.setGranted(artifactID: artifact.id, names: ["library.words"])
        _ = repo.addVersion(artifactID: artifact.id, payload: Data("<html>v2</html>".utf8), requested: ["library.words", "ai.generate"], prompt: "more", now: t0.addingTimeInterval(60))
        XCTAssertEqual(repo.artifact(id: artifact.id)?.grantedNames, ["library.words"])
        _ = repo.restore(artifactID: artifact.id, versionNumber: 1, now: t0.addingTimeInterval(120))
        XCTAssertEqual(repo.artifact(id: artifact.id)?.grantedNames, ["library.words"])
    }
}
