import XCTest
@testable import Palabra

@MainActor
final class ArtifactRepositoryTests: XCTestCase {
    private var repo: SwiftDataArtifactRepository!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        repo = SwiftDataArtifactRepository.inMemory()
    }

    private func payload(_ text: String) -> Data { Data(text.utf8) }

    @discardableResult
    private func makeArtifact(title: String = "T", text: String = "v1", now: Date? = nil) -> Artifact {
        guard case .success(let artifact) = repo.create(title: title, kind: .spec, payload: payload(text), requested: ["library.words"], prompt: "p", now: now ?? t0) else {
            XCTFail("create failed")
            fatalError()
        }
        return artifact
    }

    func testCreateStartsAtVersionOne() {
        let artifact = makeArtifact()
        XCTAssertEqual(artifact.currentVersion, 1)
        XCTAssertEqual(artifact.kind, .spec)
        let versions = repo.versions(artifactID: artifact.id)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions.first?.requestedNames, ["library.words"])
    }

    func testAddVersionBumpsAndTouches() {
        let artifact = makeArtifact()
        let later = t0.addingTimeInterval(60)
        guard case .success(let version) = repo.addVersion(artifactID: artifact.id, payload: payload("v2"), requested: [], prompt: "change", now: later) else {
            return XCTFail("addVersion failed")
        }
        XCTAssertEqual(version.number, 2)
        XCTAssertEqual(repo.artifact(id: artifact.id)?.currentVersion, 2)
        XCTAssertEqual(repo.artifact(id: artifact.id)?.updatedAt, later)
        XCTAssertEqual(repo.versions(artifactID: artifact.id).map(\.number), [2, 1])
    }

    func testAddVersionToMissingArtifactIsNotFound() {
        let result = repo.addVersion(artifactID: UUID(), payload: payload("x"), requested: [], prompt: "", now: t0)
        XCTAssertEqual(result.failureValue, .notFound)
    }

    func testPrunesToNewest20() {
        let artifact = makeArtifact()
        for i in 2...21 {
            _ = repo.addVersion(artifactID: artifact.id, payload: payload("v\(i)"), requested: [], prompt: "", now: t0.addingTimeInterval(Double(i)))
        }
        let versions = repo.versions(artifactID: artifact.id)
        XCTAssertEqual(versions.count, 20)
        XCTAssertEqual(versions.first?.number, 21)
        XCTAssertEqual(versions.last?.number, 2)
    }

    func testRestoreCopiesPayloadIntoNewVersion() {
        let artifact = makeArtifact(text: "original")
        _ = repo.addVersion(artifactID: artifact.id, payload: payload("changed"), requested: [], prompt: "c", now: t0.addingTimeInterval(1))
        guard case .success(let restored) = repo.restore(artifactID: artifact.id, versionNumber: 1, now: t0.addingTimeInterval(2)) else {
            return XCTFail("restore failed")
        }
        XCTAssertEqual(restored.number, 3)
        XCTAssertEqual(restored.payload, payload("original"))
        XCTAssertEqual(restored.prompt, "Restored version 1")
        XCTAssertEqual(restored.requestedNames, ["library.words"])
        XCTAssertEqual(repo.versions(artifactID: artifact.id).count, 3)
    }

    func testRestoreMissingVersionIsNotFound() {
        let artifact = makeArtifact()
        XCTAssertEqual(repo.restore(artifactID: artifact.id, versionNumber: 99, now: t0).failureValue, .notFound)
    }

    func testPayloadOver64KBIsRejected() {
        let ok = Data(repeating: 0x61, count: 65_536)
        let big = Data(repeating: 0x61, count: 65_537)
        XCTAssertNotNil(repo.create(title: "ok", kind: .spec, payload: ok, requested: [], prompt: "", now: t0).successValue)
        XCTAssertEqual(repo.create(title: "big", kind: .spec, payload: big, requested: [], prompt: "", now: t0).failureValue, .payloadTooLarge)
        let artifact = makeArtifact()
        XCTAssertEqual(repo.addVersion(artifactID: artifact.id, payload: big, requested: [], prompt: "", now: t0).failureValue, .payloadTooLarge)
        XCTAssertEqual(repo.artifact(id: artifact.id)?.currentVersion, 1)
    }

    func testDeleteRemovesVersionsAndState() {
        let artifact = makeArtifact()
        _ = repo.setStateValue(artifactID: artifact.id, key: "k", value: payload("v"))
        repo.delete(id: artifact.id)
        XCTAssertNil(repo.artifact(id: artifact.id))
        XCTAssertTrue(repo.versions(artifactID: artifact.id).isEmpty)
        XCTAssertNil(repo.stateValue(artifactID: artifact.id, key: "k"))
    }

    func testDeleteLeavesOtherArtifactsAlone() {
        let a = makeArtifact(title: "a")
        let b = makeArtifact(title: "b")
        _ = repo.setStateValue(artifactID: b.id, key: "k", value: payload("v"))
        repo.delete(id: a.id)
        XCTAssertNotNil(repo.artifact(id: b.id))
        XCTAssertEqual(repo.stateValue(artifactID: b.id, key: "k"), payload("v"))
    }

    func testStateRoundTripAndRemove() {
        let artifact = makeArtifact()
        XCTAssertNil(repo.stateValue(artifactID: artifact.id, key: "k"))
        _ = repo.setStateValue(artifactID: artifact.id, key: "k", value: payload("one"))
        _ = repo.setStateValue(artifactID: artifact.id, key: "k", value: payload("two"))
        XCTAssertEqual(repo.stateValue(artifactID: artifact.id, key: "k"), payload("two"))
        repo.removeStateValue(artifactID: artifact.id, key: "k")
        XCTAssertNil(repo.stateValue(artifactID: artifact.id, key: "k"))
    }

    func testStateKeyTooLong() {
        let artifact = makeArtifact()
        XCTAssertEqual(repo.setStateValue(artifactID: artifact.id, key: String(repeating: "k", count: 65), value: payload("v")).failureValue, .keyTooLong)
        XCTAssertNotNil(repo.setStateValue(artifactID: artifact.id, key: String(repeating: "k", count: 64), value: payload("v")).successValue)
    }

    func testStateOverflowAndReplaceDoesNotDoubleCount() {
        let artifact = makeArtifact()
        let id = artifact.id
        XCTAssertNotNil(repo.setStateValue(artifactID: id, key: "a", value: Data(count: 262_144)).successValue)
        XCTAssertEqual(repo.setStateValue(artifactID: id, key: "b", value: Data(count: 1)).failureValue, .storageFull)
        // Overwriting "a" swaps its size, so it still fits and frees room for "b".
        XCTAssertNotNil(repo.setStateValue(artifactID: id, key: "a", value: Data(count: 10)).successValue)
        XCTAssertNotNil(repo.setStateValue(artifactID: id, key: "b", value: Data(count: 262_134)).successValue)
        XCTAssertEqual(repo.setStateValue(artifactID: id, key: "c", value: Data(count: 1)).failureValue, .storageFull)
    }

    func testStateIsPerArtifact() {
        let a = makeArtifact(title: "a")
        let b = makeArtifact(title: "b")
        _ = repo.setStateValue(artifactID: a.id, key: "k", value: payload("A"))
        XCTAssertNil(repo.stateValue(artifactID: b.id, key: "k"))
    }

    func testArtifactsNewestUpdatedFirst() {
        let old = makeArtifact(title: "old", now: t0)
        let new = makeArtifact(title: "new", now: t0.addingTimeInterval(100))
        XCTAssertEqual(repo.artifacts().map(\.title), ["new", "old"])
        _ = repo.addVersion(artifactID: old.id, payload: payload("x"), requested: [], prompt: "", now: t0.addingTimeInterval(200))
        XCTAssertEqual(repo.artifacts().map(\.id), [old.id, new.id])
    }

    func testGrantedNamesRoundTrip() {
        let artifact = makeArtifact()
        XCTAssertEqual(artifact.grantedNames, [])
        artifact.grantedNames = ["review.flag"]
        XCTAssertEqual(artifact.grantedNames, ["review.flag"])
    }
}

private extension Result {
    var successValue: Success? { if case .success(let value) = self { return value }; return nil }
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}
