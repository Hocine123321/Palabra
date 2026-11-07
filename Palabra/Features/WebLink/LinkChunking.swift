import Foundation

/// Replies bigger than one relay frame (256 KB) are split. The whole reply message is serialised, cut into
/// pieces, and each piece travels as `{id, type: "chunk", payload: {index, total, data}}` (`data` is base64).
/// The page puts them back together by `id`. Small replies are sent as they are.
enum LinkChunking {
    /// Below the relay's frame limit once base64, the envelope and the encryption are added.
    static let maxPieceBytes = 120_000

    static func pieces(of reply: LinkMessage, maxPieceBytes: Int = maxPieceBytes) throws -> [LinkMessage] {
        let whole = try JSONEncoder().encode(reply)
        guard whole.count > maxPieceBytes else { return [reply] }
        let total = (whole.count + maxPieceBytes - 1) / maxPieceBytes
        return (0..<total).map { index in
            let slice = whole.subdata(in: (index * maxPieceBytes)..<min(whole.count, (index + 1) * maxPieceBytes))
            return LinkMessage(id: reply.id, type: "chunk", version: 1, payload: .object([
                "index": .number(Double(index)), "total": .number(Double(total)), "data": .string(slice.base64EncodedString()),
            ]))
        }
    }

    /// The inverse, used by tests and by any Swift reader of the link.
    static func reassemble(_ pieces: [LinkMessage]) throws -> LinkMessage {
        if pieces.count == 1, pieces[0].type != "chunk" { return pieces[0] }
        var parts: [Int: Data] = [:]
        var total = 0
        for piece in pieces {
            guard piece.type == "chunk", case .object(let p)? = piece.payload,
                  case .number(let i)? = p["index"], case .number(let t)? = p["total"],
                  let text = p["data"]?.stringValue, let data = Data(base64Encoded: text) else { throw CocoaError(.coderInvalidValue) }
            parts[Int(i)] = data
            total = Int(t)
        }
        guard parts.count == total, total > 0 else { throw CocoaError(.coderValueNotFound) }
        let whole = (0..<total).reduce(into: Data()) { $0.append(parts[$1] ?? Data()) }
        return try JSONDecoder().decode(LinkMessage.self, from: whole)
    }
}
