import Foundation

struct MirrorPushResult: Equatable {
    let sent: Int
    let deleted: Int
    let skipped: [String] // record ids too large to mirror
    let seq: Int?
}

/// Sends what changed since the last successful push: new and edited records as sealed items, and a tombstone for every
/// record of the given kinds that no longer exists. Nothing changed means no request at all.
struct MirrorPusher {
    static let maxSealedChars = 262_144
    static let batchItems = 200
    static let batchChars = 900_000

    let client: MirrorClient
    let secrets: MirrorSecrets
    let index: MirrorIndex

    func push(_ records: [MirrorRecord], kinds: Set<String>) async throws -> MirrorPushResult {
        guard let dataKey = Base64URL.decode(secrets.dataKey), let keys = MirrorKeys(dataKey: dataKey) else {
            throw MirrorCrypto.Failure.badKey
        }

        var current: [String: MirrorRecord] = [:] // by item id
        var order: [String] = []
        for record in records {
            let id = MirrorCrypto.itemID(keys: keys, kind: record.kind, recordID: record.recordID)
            if current[id] == nil { order.append(id) }
            current[id] = record
        }
        let changed = order.filter { itemID in
            guard let record = current[itemID] else { return false }
            return index.hash(of: itemID) != record.contentHash
        }
        let gone = kinds.flatMap { kind in index.itemIDs(ofKind: kind) }.filter { itemID in current[itemID] == nil }.sorted()
        guard !changed.isEmpty || !gone.isEmpty else { return MirrorPushResult(sent: 0, deleted: 0, skipped: [], seq: nil) }

        index.generation += 1
        let generation = index.generation

        struct Pending {
            let item: PutItem
            let kind: String
            let hash: String
        }
        var pending: [Pending] = []
        var skipped: [String] = []
        for id in changed {
            guard let record = current[id] else { continue }
            let envelope: JSONValue = .object([
                "v": .number(1), "k": .string(record.kind), "r": .string(record.recordID),
                "h": .string(record.contentHash), "g": .number(Double(generation)), "d": record.payload,
            ])
            let sealed = try MirrorCrypto.sealItem(keys: keys, itemID: id, plaintext: Data(envelope.jsonString.utf8))
            let text = Base64URL.encode(sealed)
            if text.count > Self.maxSealedChars {
                skipped.append(record.recordID)
            } else {
                pending.append(Pending(item: PutItem(id: id, sealed: text, deleted: false), kind: record.kind, hash: record.contentHash))
            }
        }
        for id in gone {
            pending.append(Pending(item: PutItem(id: id, sealed: "", deleted: true), kind: "", hash: ""))
        }

        var sent = 0, deleted = 0
        var seq: Int?
        var batch: [Pending] = []
        var chars = 0

        func flush() async throws {
            guard !batch.isEmpty else { return }
            seq = try await client.putItems(mirrorID: secrets.mirrorID, bearer: secrets.bearer, items: batch.map(\.item))
            for entry in batch {
                if entry.item.deleted {
                    index.remove(itemID: entry.item.id)
                    deleted += 1
                } else {
                    index.record(itemID: entry.item.id, kind: entry.kind, hash: entry.hash)
                    sent += 1
                }
            }
            try index.save()
            batch = []
            chars = 0
        }

        for entry in pending {
            if batch.count >= Self.batchItems || chars + entry.item.sealed.count > Self.batchChars { try await flush() }
            batch.append(entry)
            chars += entry.item.sealed.count
        }
        try await flush()
        return MirrorPushResult(sent: sent, deleted: deleted, skipped: skipped, seq: seq)
    }
}
