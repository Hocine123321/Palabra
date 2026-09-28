import Foundation

/// Normalizes Spanish word input into an identity key (diacritic-sensitive, so
/// `él ≠ el`) and a search key (diacritic-folded, so typing "ano" finds "año").
enum WordKey {
    private static let esLocale = Locale(identifier: "es")

    static func identity(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed
            .lowercased(with: esLocale)
            .precomposedStringWithCanonicalMapping
    }

    static func search(_ raw: String) -> String {
        identity(raw).folding(options: [.diacriticInsensitive], locale: esLocale)
    }

    /// Deterministic tile-tint index in `0..<count`, stable across launches
    /// (unlike Swift's per-launch-randomized `hashValue`).
    static func tintIndex(_ key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }
}
