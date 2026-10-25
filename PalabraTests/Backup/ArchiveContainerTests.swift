import XCTest
@testable import Palabra

final class ArchiveContainerTests: XCTestCase {
    private struct Meta: Codable, Equatable {
        var title: String
        var refs: [ArchiveBlobRef]
        var when: Date
        var optional: String?
    }

    private var urls: [URL] = []

    override func tearDown() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString).palabra")
        urls.append(url)
        return url
    }

    /// Writes an archive with the given blobs and returns its bytes.
    private func make(_ blobs: [Data], title: String = "Palabra") throws -> (url: URL, meta: Meta) {
        let url = tempURL()
        let writer = try ArchiveWriter(url: url)
        let refs = try blobs.map { try writer.addBlob($0) }
        let meta = Meta(title: title, refs: refs, when: Date(timeIntervalSince1970: 1_800_000_000), optional: nil)
        try writer.finish(meta: meta)
        return (url, meta)
    }

    func testRoundTripOfMetaAndBlobs() throws {
        let a = Data((0..<5_000).map { UInt8($0 % 251) })
        let b = Data()
        let c = Data(repeating: 7, count: 300_000)
        let (url, meta) = try make([a, b, c], title: "¡Hola! 🎉")
        let reader = try ArchiveReader(url: url)
        XCTAssertEqual(try reader.meta(Meta.self), meta)
        XCTAssertEqual(reader.blob(meta.refs[0]), a)
        XCTAssertEqual(reader.blob(meta.refs[1]), b)
        XCTAssertEqual(reader.blob(meta.refs[2]), c)
    }

    func testCompressibleDataIsStoredSmaller() throws {
        let big = Data(repeating: 0, count: 500_000)
        let (url, _) = try make([big])
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).intValue
        XCTAssertLessThan(size, 20_000)
    }

    func testFileThatIsNotAnArchive() {
        XCTAssertThrowsError(try ArchiveReader(data: Data("{\"app\":\"Palabra\"}".utf8))) {
            XCTAssertEqual($0 as? ArchiveError, .notAnArchive)
        }
        XCTAssertThrowsError(try ArchiveReader(data: Data())) { XCTAssertEqual($0 as? ArchiveError, .notAnArchive) }
    }

    func testTruncatedFileIsReportedAsIncomplete() throws {
        let (url, _) = try make([Data(repeating: 1, count: 10_000)])
        let full = try Data(contentsOf: url)
        for cut in [5, 8, full.count / 2, full.count - 1] {
            XCTAssertThrowsError(try ArchiveReader(data: full.prefix(cut))) { error in
                XCTAssertEqual(error as? ArchiveError, .incomplete, "cut at \(cut)")
            }
        }
    }

    func testNewerVersionIsRefused() throws {
        let (url, _) = try make([])
        var data = try Data(contentsOf: url)
        data[4] = 99
        XCTAssertThrowsError(try ArchiveReader(data: data)) { XCTAssertEqual($0 as? ArchiveError, .unsupportedVersion(99)) }
    }

    func testDamagedMetaIsCorrupt() throws {
        let (url, meta) = try make([Data(repeating: 3, count: 1_000)])
        var data = try Data(contentsOf: url)
        let footer = data.count - ArchiveFormat.footerSize
        let metaStart = Int(meta.refs[0].offset) + Int(meta.refs[0].length)
        data[(metaStart + footer) / 2] ^= 0xFF
        XCTAssertThrowsError(try ArchiveReader(data: data)) { XCTAssertEqual($0 as? ArchiveError, .corrupt) }
    }

    func testDamagedBlobIsDroppedButTheRestStillReads() throws {
        let first = Data(repeating: 1, count: 4_000)
        let second = Data((0..<4_000).map { UInt8($0 % 200) })
        let (url, meta) = try make([first, second])
        var data = try Data(contentsOf: url)
        data[Int(meta.refs[0].offset) + 2] ^= 0xFF
        let reader = try ArchiveReader(data: data)
        XCTAssertNil(reader.blob(meta.refs[0]))
        XCTAssertEqual(reader.blob(meta.refs[1]), second)
    }

    func testBlobReferencesOutsideTheFileAreRejectedWithoutCrashing() throws {
        let (url, _) = try make([Data(repeating: 1, count: 100)])
        let reader = try ArchiveReader(url: url)
        XCTAssertNil(reader.blob(ArchiveBlobRef(offset: 0, length: 10, rawLength: 10, crc: 0)))
        XCTAssertNil(reader.blob(ArchiveBlobRef(offset: UInt64.max, length: UInt32.max, rawLength: 1, crc: 0)))
        XCTAssertNil(reader.blob(ArchiveBlobRef(offset: 8, length: UInt32.max, rawLength: 1, crc: 0)))
        XCTAssertNil(reader.blob(ArchiveBlobRef(offset: UInt64(Int.max), length: 5, rawLength: 5, crc: 0)))
    }

    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testWriterReportsAnUnwritableLocation() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)/x.palabra")
        XCTAssertThrowsError(try ArchiveWriter(url: url)) { XCTAssertEqual($0 as? ArchiveError, .writeFailed) }
    }

    func testCancelRemovesTheHalfWrittenFile() throws {
        let url = tempURL()
        let writer = try ArchiveWriter(url: url)
        _ = try writer.addBlob(Data(repeating: 1, count: 10))
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
