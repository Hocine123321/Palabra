import Foundation
import Observation

enum MirrorSyncError: Equatable {
    case offline, rejected, rateLimited, other
}

/// The phone's Mirroring as the rest of the app sees it: paired or not, on or off, the last sync and what to do next.
/// Nothing here touches the network unless the phone is paired and the person has Mirroring turned on.
@MainActor
@Observable
final class MirrorService {
    private(set) var lastSyncAt: Date?
    private(set) var lastError: MirrorSyncError?
    private(set) var syncing = false
    private var stored: MirrorSecrets?
    private var settingsValue: MirrorSettings

    private let secrets: MirrorSecretsStore
    private let settings: MirrorSettingsStore
    private let index: MirrorIndex
    private let session: URLSession
    private let now: () -> Date
    private var lastAttemptAt: Date?
    /// A sync more often than this is skipped (launch plus foreground plus a tab change would otherwise push three times).
    static let minimumInterval: TimeInterval = 30

    init(
        secrets: MirrorSecretsStore = MirrorSecretsStore(),
        settings: MirrorSettingsStore = MirrorSettingsStore(),
        index: MirrorIndex = .standard(),
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.secrets = secrets
        self.settings = settings
        self.index = index
        self.session = session
        self.now = now
        stored = secrets.load()
        settingsValue = settings.value
        lastSyncAt = settingsValue.lastSyncAt
    }

    /// A service on throwaway storage (its own Keychain slot, defaults suite and temp file), for tests and previews.
    static func inMemory() -> MirrorService {
        let suite = "mirror-inmemory-\(UUID().uuidString)"
        return MirrorService(
            secrets: MirrorSecretsStore(keychain: KeychainStore(account: "mirror-secrets-\(UUID().uuidString)")),
            settings: MirrorSettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard),
            index: MirrorIndex(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("mirror-\(UUID().uuidString)/index.json"))
        )
    }

    // MARK: State

    var isPaired: Bool { stored != nil }
    var computers: [MirrorComputer] { stored?.computers ?? [] }

    var enabled: Bool {
        get { settingsValue.enabled }
        set {
            settingsValue.enabled = newValue
            settings.value = settingsValue
        }
    }

    // MARK: Pairing

    func makePairingSession(link: PairingLink) -> MirrorPairingSession {
        MirrorPairingSession(link: link, client: MirrorClient(origin: link.origin, session: session), secrets: secrets)
    }

    /// Call when a pairing session finished: picks up the new secrets and switches Mirroring on.
    func didPair() {
        stored = secrets.load()
        if stored != nil { enabled = true }
    }

    // MARK: Sync

    /// Pushes what changed. Never throws; the outcome is in `lastSyncAt` and `lastError`.
    func sync(records: [MirrorRecord], force: Bool = false) async {
        guard let current = stored, enabled || force, !syncing else { return }
        if !force, let last = lastAttemptAt, now().timeIntervalSince(last) < Self.minimumInterval { return }
        guard let origin = URL(string: current.origin) else {
            lastError = .other
            return
        }
        syncing = true
        lastAttemptAt = now()
        defer { syncing = false }
        let pusher = MirrorPusher(client: MirrorClient(origin: origin, session: session), secrets: current, index: index, now: now)
        do {
            let result = try await pusher.push(records, kinds: ["word"])
            try await pushManifestIfDue(with: pusher, after: result)
            lastSyncAt = now()
            settingsValue.lastSyncAt = lastSyncAt
            settings.value = settingsValue
            lastError = nil
        } catch {
            lastError = Self.syncError(for: error)
        }
    }

    /// The manifest goes last, in its own request, when something was sent, the id list changed, or it has gone stale.
    private func pushManifestIfDue(with pusher: MirrorPusher, after result: MirrorPushResult) async throws {
        let ids = index.itemIDs(excludingKind: MirrorManifest.kind)
        let hash = MirrorManifest.idsHash(ids)
        let stale = settingsValue.lastManifestAt.map { now().timeIntervalSince($0) >= MirrorManifest.heartbeat } ?? true
        guard result.sent + result.deleted > 0 || hash != settingsValue.lastManifestIDsHash || stale else { return }
        let record = MirrorManifest.record(ids: ids, counts: index.counts(excludingKind: MirrorManifest.kind), now: now())
        _ = try await pusher.push([record], kinds: [MirrorManifest.kind])
        settingsValue.lastManifestAt = now()
        settingsValue.lastManifestIDsHash = hash
        settings.value = settingsValue
    }

    // MARK: Computers

    /// Revokes the computer's token on the Worker; it is dropped from the list only when that worked.
    func remove(computerID: String) async {
        guard var current = stored else { return }
        guard let origin = URL(string: current.origin) else { return }
        do {
            try await MirrorClient(origin: origin, session: session).removeDevice(mirrorID: current.mirrorID, bearer: current.bearer, deviceID: computerID)
        } catch let error as MirrorClientError {
            // Already gone on the Worker counts as removed.
            guard case .http(let status, _) = error, status == 404 else {
                lastError = Self.syncError(for: error)
                return
            }
        } catch {
            lastError = .other
            return
        }
        current.computers.removeAll { $0.id == computerID }
        if secrets.save(current) { stored = current }
    }

    /// Forgets the keys, the push index and the settings on this phone. The encrypted copy stays on the Worker.
    func turnOffAndForget() {
        secrets.clear()
        index.reset()
        settingsValue = MirrorSettings()
        settings.value = settingsValue
        stored = nil
        lastSyncAt = nil
        lastError = nil
        lastAttemptAt = nil
    }

    private static func syncError(for error: Error) -> MirrorSyncError {
        guard let client = error as? MirrorClientError else { return .other }
        switch client {
        case .offline: return .offline
        case .badResponse: return .other
        case .http(let status, _):
            if status == 401 || status == 403 { return .rejected }
            if status == 429 { return .rateLimited }
            return .other
        }
    }
}
