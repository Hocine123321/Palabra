import XCTest
@testable import Palabra

@MainActor
final class ArtifactApprovalTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("review.flag", .write),
        makeCapability("ai.generate", .ai),
        makeCapability("storage.get", .local),
    ])

    private func names(_ capabilities: [Capability]) -> [String] { capabilities.map(\.name) }

    func testPendingListsOnlyUngrantedNonAutoCapabilities() {
        let pending = ArtifactApproval.pending(kind: .app, requested: ["library.words", "storage.get", "ai.generate"], granted: ["library.words"], registry: registry)
        XCTAssertEqual(names(pending), ["ai.generate"])
    }

    func testPendingIsSortedAndUnique() {
        let pending = ArtifactApproval.pending(kind: .app, requested: ["review.flag", "ai.generate", "review.flag", "nope"], granted: [], registry: registry)
        XCTAssertEqual(names(pending), ["ai.generate", "review.flag"])
    }

    func testSpecNeverNeedsApprovalForReads() {
        XCTAssertTrue(ArtifactApproval.pending(kind: .spec, requested: ["library.words", "storage.get"], granted: [], registry: registry).isEmpty)
    }

    func testPendingIsTheDeltaOnUpdate() {
        // v1 was approved for reads; v2 also wants the AI.
        let pending = ArtifactApproval.pending(kind: .app, requested: ["library.words", "ai.generate"], granted: ["library.words"], registry: registry)
        XCTAssertEqual(names(pending), ["ai.generate"])
    }

    func testEffectiveIsRequestedIntersectGrantedPlusLocal() {
        let effective = ArtifactApproval.effective(kind: .app, requested: ["library.words", "ai.generate", "storage.get", "nope"], granted: ["library.words", "review.flag"], registry: registry)
        // ai.generate was denied, review.flag was granted but not requested, nope is unknown.
        XCTAssertEqual(effective, ["library.words", "storage.get"])
    }

    func testDeniedCapabilityReturnsNotGrantedThroughTheRegistry() async {
        let effective = ArtifactApproval.effective(kind: .app, requested: ["library.words", "ai.generate"], granted: ["library.words"], registry: registry)
        let session = ArtifactSession(artifactID: UUID(), dryRun: false)
        let denied = await registry.call(name: "ai.generate", args: .object([:]), session: session, granted: effective)
        XCTAssertEqual(denied, .failure(.notGranted))
        let allowed = await registry.call(name: "library.words", args: .object([:]), session: session, granted: effective)
        guard case .success = allowed else { return XCTFail("granted read must work") }
    }

    func testRestoredOldVersionKeepsTheArtifactsGrants() {
        let repo = SwiftDataArtifactRepository.inMemory()
        guard case .success(let artifact) = repo.create(title: "T", kind: .app, payload: Data("<html>1</html>".utf8), requested: ["library.words"], prompt: "p", now: Date(timeIntervalSince1970: 1_000_000)) else {
            return XCTFail("create failed")
        }
        repo.setGranted(artifactID: artifact.id, names: ["library.words"])
        _ = repo.addVersion(artifactID: artifact.id, payload: Data("<html>2</html>".utf8), requested: ["library.words", "ai.generate"], prompt: "more", now: Date(timeIntervalSince1970: 1_000_060))
        // The person denied the new capability, then restored v1.
        _ = repo.restore(artifactID: artifact.id, versionNumber: 1, now: Date(timeIntervalSince1970: 1_000_120))
        let current = repo.artifact(id: artifact.id)
        let requested = repo.versions(artifactID: artifact.id).first { $0.number == current?.currentVersion }?.requestedNames ?? []
        XCTAssertEqual(requested, ["library.words"])
        XCTAssertTrue(ArtifactApproval.pending(kind: .app, requested: requested, granted: Set(current?.grantedNames ?? []), registry: registry).isEmpty)
    }
}
