import Foundation

/// What the page saw of a word's placement (section and tags), as one plain string both sides can build the same way.
/// A `words.place` from the page carries it; the phone builds it again from the live word and refuses on a mismatch,
/// so a change made on the phone in the meantime is never silently overwritten. Plain text, not a hash, so a
/// difference is readable in tests and two different placements can never share a token.
enum PlacementToken {
    /// `category|tag1,tag2` with tags sorted by their UTF-8 bytes (the same order on both sides); `\`, `|` and `,` inside a value are escaped with a backslash.
    static func make(category: String?, tags: [String]) -> String {
        let cat = escape(category ?? "")
        let list = tags.map(escape).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }.joined(separator: ",")
        return "\(cat)|\(list)"
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if ch == "\\" || ch == "|" || ch == "," { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
