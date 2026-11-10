import Foundation

/// Artifact pages and the latest chat as mirror records. Like the other `AppEnvironment+Mirror*` files, this is where the
/// Artifact and Chat types are turned into plain JSON; `Features/Mirroring` never sees them.
extension AppEnvironment {
    /// The most characters of chat text one mirrored conversation carries; older turns are dropped first, so one item stays
    /// well below the Worker's per-item cap.
    static let mirrorChatTextBudget = 150_000

    /// Collections `artifact` (every spec artifact with its bound tables and charts resolved by the phone; apps are listed
    /// with `blocks: null`) and `chat` (the most recently updated conversation, or none). Both always count as built.
    func mirrorContentCollections() async -> [MirrorCollection] {
        [MirrorCollection(kind: "artifact", records: await mirrorArtifactRecords()), MirrorCollection(kind: "chat", records: mirrorChatRecords())]
    }

    private func mirrorArtifactRecords() async -> [MirrorRecord] {
        let formatter = ISO8601DateFormatter()
        var records: [MirrorRecord] = []
        for artifact in artifacts.artifacts() {
            let version = artifacts.versions(artifactID: artifact.id).first { $0.number == artifact.currentVersion }
            var blocks: JSONValue = .null
            if artifact.kind == .spec {
                // A spec that no longer decodes is left out, the same way the app shows "Couldn't load data" for it.
                guard let version, let spec = try? JSONDecoder().decode(ArtifactSpec.self, from: version.payload) else { continue }
                let granted = GrantPolicy.effectiveGrant(kind: .spec, requested: version.requestedNames, granted: [], registry: capabilities)
                let session = ArtifactSession(artifactID: artifact.id, dryRun: true)
                var resolved: [JSONValue] = []
                for block in spec.blocks { resolved.append(await mirrorResolve(block, session: session, granted: granted)) }
                blocks = .array(resolved)
            }
            let payload: JSONValue = .object([
                "id": .string(artifact.id.uuidString),
                "title": .string(artifact.title),
                "kind": .string(artifact.kind.rawValue),
                "version": .number(Double(artifact.currentVersion)),
                "updatedAt": .string(formatter.string(from: artifact.updatedAt)),
                "blocks": blocks,
            ])
            records.append(MirrorRecord(kind: "artifact", recordID: artifact.id.uuidString, payload: payload))
        }
        return records
    }

    /// One block as JSON, with tables and charts holding their data inline. Uses the existing `Codable` block encoding.
    private func mirrorResolve(_ block: SpecBlock, session: ArtifactSession, granted: Set<String>) async -> JSONValue {
        let failed: JSONValue = .object(["type": .string("error"), "message": .string(SpecBindLoader.loadFailedMessage)])
        switch block {
        case .table(let table):
            switch await SpecBindLoader.table(table, registry: capabilities, session: session, granted: granted) {
            case .failed: return failed
            case .loaded(let data):
                let columns: [JSONValue] = data.columns.map { JSONValue.object(["title": JSONValue.string($0)]) }
                let rows: [JSONValue] = data.rows.map { row in JSONValue.array(row.map { JSONValue.string($0) }) }
                return .object(["type": .string("table"), "columns": .array(columns), "rows": .array(rows)])
            }
        case .chart(let chart):
            switch await SpecBindLoader.chart(chart, registry: capabilities, session: session, granted: granted) {
            case .failed: return failed
            case .loaded(let data):
                let series: [JSONValue] = data.series.map { item -> JSONValue in
                    let name: JSONValue = item.name.map { JSONValue.string($0) } ?? .null
                    let values: [JSONValue] = item.values.map { JSONValue.number($0) }
                    return JSONValue.object(["name": name, "values": JSONValue.array(values)])
                }
                var object: [String: JSONValue] = [
                    "type": .string("chart"),
                    "style": .string(chart.style.rawValue),
                    "labels": .array(data.labels.map { JSONValue.string($0) }),
                    "series": .array(series),
                ]
                if let title = chart.title { object["title"] = .string(title) }
                return .object(object)
            }
        case .columns(let children):
            var resolved: [JSONValue] = []
            for child in children { resolved.append(await mirrorResolve(child, session: session, granted: granted)) }
            return .object(["type": .string("columns"), "children": .array(resolved)])
        case .section(let title, let children):
            var resolved: [JSONValue] = []
            for child in children { resolved.append(await mirrorResolve(child, session: session, granted: granted)) }
            return .object(["type": .string("section"), "title": .string(title), "children": .array(resolved)])
        default:
            return (try? JSONEncoder().encode(block)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? failed
        }
    }

    private func mirrorChatRecords() -> [MirrorRecord] {
        guard let latest = chat.conversations().first else { return [] }
        let formatter = ISO8601DateFormatter()
        // Newest turns first until the text budget is spent, then back to reading order.
        var kept: [ChatTurn] = []
        var used = 0
        for turn in latest.turns.reversed() {
            used += turn.text.count
            if used > Self.mirrorChatTextBudget, !kept.isEmpty { break }
            kept.append(turn)
        }
        let turns: [JSONValue] = kept.reversed().map { turn -> JSONValue in
            JSONValue.object([
                "role": .string(turn.role.rawValue),
                "text": .string(turn.text),
                "createdAt": .string(formatter.string(from: turn.createdAt)),
                "status": .string(turn.status.rawValue),
            ])
        }
        let payload: JSONValue = .object([
            "id": .string(latest.id.uuidString),
            "title": .string(latest.title),
            "wordId": latest.wordID.map { JSONValue.string($0.uuidString) } ?? .null,
            "updatedAt": .string(formatter.string(from: latest.updatedAt)),
            "turns": .array(turns),
        ])
        return [MirrorRecord(kind: "chat", recordID: "latest", payload: payload)]
    }
}
