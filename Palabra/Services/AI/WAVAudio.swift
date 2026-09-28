import Foundation

/// Normalizes Gemini TTS output into a WAV file `AVAudioPlayer` can play
/// directly.
///
/// Different Gemini TTS model generations default to different unary-request
/// formats: newer models (Gemini 3.8 TTS) return a complete WAV file (RIFF
/// header included); older preview models (Gemini 3.1 Flash TTS Preview,
/// Gemini 2.5 Pro Preview TTS) return headerless raw 16-bit little-endian PCM
/// at 24 kHz mono. Since the app lets the user pick any TTS-capable model,
/// this inspects what actually came back rather than assuming one or the
/// other.
enum WAVAudio {
    static func normalize(_ data: Data, mimeType: String?) -> Data {
        // Already a RIFF/WAVE container (covers the documented "AUDIO_WAV"
        // case, and is a safe check even if the mimeType string is missing
        // or unrecognized).
        if data.count >= 12, Array(data.prefix(4)) == Array("RIFF".utf8) {
            return data
        }
        let mime = mimeType?.lowercased() ?? ""
        let rate = sampleRate(fromMimeType: mime) ?? 24000
        return wav(fromPCM: data, sampleRate: rate, channels: 1, bitsPerSample: 16)
    }

    /// Builds a standard 44-byte-header PCM WAV file from raw samples.
    static func wav(fromPCM pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.appendLittleEndian(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.appendLittleEndian(UInt32(16)) // fmt chunk size for PCM
        header.appendLittleEndian(UInt16(1)) // audio format: PCM
        header.appendLittleEndian(UInt16(channels))
        header.appendLittleEndian(UInt32(sampleRate))
        header.appendLittleEndian(UInt32(byteRate))
        header.appendLittleEndian(UInt16(blockAlign))
        header.appendLittleEndian(UInt16(bitsPerSample))
        header.append(contentsOf: Array("data".utf8))
        header.appendLittleEndian(UInt32(pcm.count))
        return header + pcm
    }

    /// Looks for a `rate=NNNN` component in a mime type like
    /// `"audio/L16;codec=pcm;rate=24000"`.
    private static func sampleRate(fromMimeType mime: String) -> Int? {
        for part in mime.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("rate="), let value = Int(trimmed.dropFirst("rate=".count)) {
                return value
            }
        }
        return nil
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
