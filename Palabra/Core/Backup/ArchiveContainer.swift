import Foundation

/// Why an archive could not be written or read.
enum ArchiveError: Error, Equatable {
    /// Does not start with the archive marker (the caller may try an older format).
    case notAnArchive
    /// Written by a newer version of the app than this one.
    case unsupportedVersion(Int)
    /// The end of the file is missing: the copy or download was cut short.
    case incomplete
    /// The bytes do not match their checksum.
    case corrupt
    case writeFailed
}

/// CRC-32 (the zip/PNG polynomial), to notice a damaged or truncated file.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1) }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Where one compressed blob (for example a pronunciation clip) sits inside the archive file.
struct ArchiveBlobRef: Codable, Equatable, Sendable {
    var offset: UInt64
    var length: UInt32
    var rawLength: UInt32
    var crc: UInt32
}

/// A single-file container for a library backup.
///
/// ```
/// header   "PLBR", version (1 byte), 3 reserved bytes                       8 bytes
/// blobs    each one zlib-compressed, written one after the other
/// meta     zlib-compressed binary property list (the text of the library, with a `ArchiveBlobRef` per blob)
/// footer   meta offset (8) | meta length (4) | meta raw length (4) | meta CRC-32 (4) | "PLBE"   24 bytes
/// ```
/// Binary data is stored as bytes, not as base64 text, and blobs are written one at a time, so neither exporting nor
/// importing needs the whole library in memory. The footer is last, so a file that was cut short is recognised.
enum ArchiveFormat {
    static let magic = Data("PLBR".utf8)
    static let endMagic = Data("PLBE".utf8)
    static let version: UInt8 = 1
    static let headerSize = 8
    static let footerSize = 24

    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        return try (data as NSData).compressed(using: .zlib) as Data
    }

    static func decompress(_ data: Data, expectedLength: Int) throws -> Data {
        if expectedLength == 0 { return Data() }
        guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data, raw.count == expectedLength else {
            throw ArchiveError.corrupt
        }
        return raw
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    mutating func appendBigEndian(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) { append(UInt8((value >> UInt64(shift)) & 0xFF)) }
    }

    func bigEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(self[startIndex + offset + $1]) }
    }

    func bigEndianUInt64(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(self[startIndex + offset + $1]) }
    }
}

/// Writes an archive to a file: `addBlob` as many times as needed, then `finish` with the metadata.
final class ArchiveWriter {
    private let url: URL
    private let handle: FileHandle
    private var offset: UInt64 = 0

    init(url: URL) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw ArchiveError.writeFailed }
        self.handle = handle
        var header = ArchiveFormat.magic
        header.append(contentsOf: [ArchiveFormat.version, 0, 0, 0])
        try write(header)
    }

    private func write(_ data: Data) throws {
        do {
            try handle.write(contentsOf: data)
            offset += UInt64(data.count)
        } catch {
            throw ArchiveError.writeFailed
        }
    }

    func addBlob(_ raw: Data) throws -> ArchiveBlobRef {
        let packed = try ArchiveFormat.compress(raw)
        let ref = ArchiveBlobRef(offset: offset, length: UInt32(packed.count), rawLength: UInt32(raw.count), crc: CRC32.checksum(packed))
        try write(packed)
        return ref
    }

    /// Writes the metadata and the footer, and closes the file.
    func finish<Meta: Encodable>(meta: Meta) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let raw = try? encoder.encode(meta) else { throw ArchiveError.writeFailed }
        let packed = try ArchiveFormat.compress(raw)
        let metaOffset = offset
        try write(packed)
        var footer = Data()
        footer.appendBigEndian(metaOffset)
        footer.appendBigEndian(UInt32(packed.count))
        footer.appendBigEndian(UInt32(raw.count))
        footer.appendBigEndian(CRC32.checksum(packed))
        footer.append(ArchiveFormat.endMagic)
        try write(footer)
        try? handle.close()
    }

    /// Gives up: closes and removes the half-written file.
    func cancel() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

/// Reads an archive. The file is memory-mapped, so a large one is not loaded up front; each blob is read, checked and
/// decompressed only when asked for.
struct ArchiveReader: Sendable {
    private let data: Data
    private let metaOffset: Int
    private let metaLength: Int
    private let metaRawLength: Int

    init(url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw ArchiveError.notAnArchive }
        try self.init(data: data)
    }

    init(data: Data) throws {
        guard data.count >= 4, data.prefix(4) == ArchiveFormat.magic else { throw ArchiveError.notAnArchive }
        guard data.count >= ArchiveFormat.headerSize else { throw ArchiveError.incomplete }
        let version = Int(data[data.startIndex + 4])
        guard version <= Int(ArchiveFormat.version) else { throw ArchiveError.unsupportedVersion(version) }
        guard data.count >= ArchiveFormat.headerSize + ArchiveFormat.footerSize,
              data.suffix(4) == ArchiveFormat.endMagic else { throw ArchiveError.incomplete }
        let footer = data.count - ArchiveFormat.footerSize
        let offset = data.bigEndianUInt64(at: footer)
        let length = Int(data.bigEndianUInt32(at: footer + 8))
        let rawLength = Int(data.bigEndianUInt32(at: footer + 12))
        let crc = data.bigEndianUInt32(at: footer + 16)
        guard offset >= UInt64(ArchiveFormat.headerSize), offset <= UInt64(footer), Int(offset) + length == footer else { throw ArchiveError.corrupt }
        let packed = data.subdata(in: (data.startIndex + Int(offset))..<(data.startIndex + footer))
        guard CRC32.checksum(packed) == crc else { throw ArchiveError.corrupt }
        self.data = data
        metaOffset = Int(offset)
        metaLength = length
        metaRawLength = rawLength
    }

    func meta<Meta: Decodable>(_ type: Meta.Type) throws -> Meta {
        let packed = data.subdata(in: (data.startIndex + metaOffset)..<(data.startIndex + metaOffset + metaLength))
        let raw = try ArchiveFormat.decompress(packed, expectedLength: metaRawLength)
        guard let meta = try? PropertyListDecoder().decode(Meta.self, from: raw) else { throw ArchiveError.corrupt }
        return meta
    }

    /// The blob's bytes, or nil when it lies outside the file, fails its checksum or does not decompress.
    func blob(_ ref: ArchiveBlobRef) -> Data? {
        // Range checks first, in the wide type, so a hostile reference cannot overflow the arithmetic below.
        guard ref.offset >= UInt64(ArchiveFormat.headerSize), ref.offset <= UInt64(metaOffset),
              UInt64(metaOffset) - ref.offset >= UInt64(ref.length) else { return nil }
        let start = Int(ref.offset)
        let end = start + Int(ref.length)
        let packed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
        guard CRC32.checksum(packed) == ref.crc else { return nil }
        return try? ArchiveFormat.decompress(packed, expectedLength: Int(ref.rawLength))
    }
}
