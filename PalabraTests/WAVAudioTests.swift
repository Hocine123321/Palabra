import XCTest
@testable import Palabra

/// Reads little-endian integers by indexing individual bytes — deliberately
/// avoids `Data.withUnsafeBytes` on a sub-range here, since a `Data` slice's
/// `startIndex` is not rebased to 0 and mixing that with pointer-based loads
/// is a well-known footgun. Plain byte indexing + shifting has no such
/// ambiguity and needs nothing beyond what `Data`'s subscript guarantees.
private func u32LE(_ data: Data, at start: Int) -> UInt32 {
    UInt32(data[data.startIndex + start])
        | (UInt32(data[data.startIndex + start + 1]) << 8)
        | (UInt32(data[data.startIndex + start + 2]) << 16)
        | (UInt32(data[data.startIndex + start + 3]) << 24)
}

private func u16LE(_ data: Data, at start: Int) -> UInt16 {
    UInt16(data[data.startIndex + start]) | (UInt16(data[data.startIndex + start + 1]) << 8)
}

final class WAVAudioTests: XCTestCase {
    func testNormalizePassesThroughExistingWAVUnchanged() {
        let existingWAV = WAVAudio.wav(fromPCM: Data([1, 2, 3, 4]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        let result = WAVAudio.normalize(existingWAV, mimeType: "audio/wav")
        XCTAssertEqual(result, existingWAV)
    }

    func testNormalizeWrapsHeaderlessPCMUsingRateFromMimeType() {
        let pcm = Data(repeating: 0xAB, count: 10)
        let result = WAVAudio.normalize(pcm, mimeType: "audio/L16;codec=pcm;rate=16000")

        // 44-byte canonical header + the original PCM payload appended verbatim.
        XCTAssertEqual(result.count, 44 + pcm.count)
        XCTAssertEqual(Array(result.suffix(pcm.count)), Array(pcm))
        XCTAssertEqual(u32LE(result, at: 24), 16000) // sample rate field
    }

    func testNormalizeDefaultsTo24kHzWhenMimeTypeHasNoRate() {
        let result = WAVAudio.normalize(Data(repeating: 0x11, count: 6), mimeType: "audio/L16")
        XCTAssertEqual(u32LE(result, at: 24), 24000)
    }

    func testNormalizeDefaultsTo24kHzWhenMimeTypeIsNil() {
        let result = WAVAudio.normalize(Data(repeating: 0x11, count: 6), mimeType: nil)
        XCTAssertEqual(u32LE(result, at: 24), 24000)
    }

    func testNormalizeDetectsRiffEvenWithoutMimeTypeHint() {
        // A model that mislabels its mimeType (or omits it) but still returns
        // a real WAV file should still be passed through, not double-wrapped.
        let existingWAV = WAVAudio.wav(fromPCM: Data([9, 9, 9]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        let result = WAVAudio.normalize(existingWAV, mimeType: nil)
        XCTAssertEqual(result, existingWAV)
    }

    func testWavHeaderFieldsAreCorrectForMonoSixteenBit() {
        let pcm = Data(repeating: 0x7F, count: 100)
        let result = WAVAudio.wav(fromPCM: pcm, sampleRate: 24000, channels: 1, bitsPerSample: 16)

        XCTAssertEqual(result.count, 44 + 100)
        XCTAssertEqual(Array(result[result.startIndex..<result.startIndex + 4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(result[(result.startIndex + 8)..<(result.startIndex + 12)]), Array("WAVE".utf8))
        XCTAssertEqual(Array(result[(result.startIndex + 12)..<(result.startIndex + 16)]), Array("fmt ".utf8))
        XCTAssertEqual(Array(result[(result.startIndex + 36)..<(result.startIndex + 40)]), Array("data".utf8))

        XCTAssertEqual(u32LE(result, at: 4), UInt32(36 + 100)) // RIFF chunk size
        XCTAssertEqual(u32LE(result, at: 16), 16) // fmt chunk size (PCM)
        XCTAssertEqual(u16LE(result, at: 20), 1) // audio format: PCM
        XCTAssertEqual(u16LE(result, at: 22), 1) // channels: mono
        XCTAssertEqual(u32LE(result, at: 24), 24000) // sample rate
        XCTAssertEqual(u32LE(result, at: 28), 24000 * 1 * 16 / 8) // byte rate
        XCTAssertEqual(u16LE(result, at: 32), UInt16(1 * 16 / 8)) // block align
        XCTAssertEqual(u16LE(result, at: 34), 16) // bits per sample
        XCTAssertEqual(u32LE(result, at: 40), 100) // data chunk size
    }

    func testStubSampleAudioIsAPlayableWAV() {
        let audio = StubAIClient.sampleAudio()
        XCTAssertGreaterThan(audio.count, 44)
        XCTAssertEqual(Array(audio.prefix(4)), Array("RIFF".utf8))
        // Declared data size must match what's actually there after the header.
        XCTAssertEqual(Int(u32LE(audio, at: 40)), audio.count - 44)
    }

    func testWavHeaderTotalSizeIsFortyFourBytes() {
        let result = WAVAudio.wav(fromPCM: Data(), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(result.count, 44)
    }
}
