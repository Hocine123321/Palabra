import Foundation
import Observation

enum MirrorSyncError: Equatable {
    case offline, rejected, rateLimited, full, other
}

/// The phone's Mirroring as the rest of the app sees it: paired or not, on or off, the last sync and what to do next.
/// Nothing here touches the network unless the phone is paired and the person has Mirroring turned on.
@MainActor
@Observable
final class MirrorService {
    private(set) var lastSyncAt: Date?
    private(set) var lastError: MirrorSyncError?
    private(set) var syncing = false
    /// Names of the computers the last removal also dropped, because they were paired before key rotation existed and so
    /// could not be given the new key. Cleared by the next removal.
    private(set) var lastDroppedNames: [String] = []
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
    /// Computers paired before key rotation existed: a rotation cannot reach them, so they must pair again to survive one.
    var computersNeedingRepair: [MirrorComputer] { computers.filter { $0.deviceKey == nil } }

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
    func sync(collections: [MirrorCollection], force: Bool = false) async {
        guard stored != nil, enabled || force, !syncing else { return }
        if !force, let last = lastAttemptAt, now().timeIntervalSince(last) < Self.minimumInterval { return }
        syncing = true
        lastAttemptAt = now()
        defer { syncing = false }
        // A rotation whose outcome is unknown must be settled first: until then it is not clear which key the Worker's data is under.
        guard await settlePendingRotation(), let current = stored, let origin = URL(string: current.origin) else {
            if lastError == nil { lastError = .other }
            return
        }
        let pusher = MirrorPusher(client: MirrorClient(origin: origin, session: session), secrets: current, index: index, now: now)
        do {
            let result = try await pusher.push(collections.flatMap(\.records), kinds: Set(collections.map(\.kind)))
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

    /// Removes a computer and replaces the data key, so the removed computer cannot read anything sent from now on.
    ///
    /// One Worker call does it all: the new key goes to every remaining computer sealed under its own device key, the removed
    /// computer's token is revoked and every item sealed under the old key is deleted. The new key is saved as `pending` in the
    /// Keychain before that call, so a crash or a lost reply never leaves the phone without the key the Worker's data is under.
    /// A computer without a device key (paired before rotation existed) cannot be given the new key; it is removed too.
    /// The caller should sync afterwards: the library is sent again under the new key.
    func remove(computerID: String) async {
        lastDroppedNames = []
        guard stored != nil, await settlePendingRotation(), var current = stored,
              let origin = URL(string: current.origin) else { return }
        let client = MirrorClient(origin: origin, session: session)
        let others = current.computers.filter { $0.id != computerID }
        var blobs: [String: String] = [:]
        var dropped: [MirrorComputer] = []
        let newKey = MirrorCrypto.randomBytes(32)
        let epoch = current.epoch + 1
        for computer in others {
            if let text = computer.deviceKey, let deviceKey = Base64URL.decode(text), deviceKey.count == 32,
               let sealed = try? MirrorCrypto.sealRotation(deviceKey: deviceKey, mirrorID: current.mirrorID, deviceID: computer.id, epoch: epoch, dataKey: newKey) {
                blobs[computer.id] = Base64URL.encode(sealed)
            } else {
                dropped.append(computer)
            }
        }
        current.pending = MirrorSecrets.Pending(dataKey: Base64URL.encode(newKey), epoch: epoch, removedIDs: [computerID] + dropped.map(\.id))
        guard secrets.save(current) else {
            lastError = .other
            return
        }
        stored = current
        do {
            _ = try await client.rotate(mirrorID: current.mirrorID, bearer: current.bearer, epoch: epoch, remove: computerID, blobs: blobs)
        } catch let error as MirrorClientError {
            await rotationFailed(error, computerID: computerID, client: client)
            return
        } catch {
            lastError = .other
            return
        }
        lastDroppedNames = dropped.map(\.name)
        promotePending()
        lastError = nil
    }

    /// The Worker did not rotate (or the reply was lost). Decides what the phone keeps.
    private func rotationFailed(_ error: MirrorClientError, computerID: String, client: MirrorClient) async {
        guard var current = stored, let pending = current.pending else { return }
        switch error {
        case .offline, .badResponse:
            // Unknown whether the Worker applied it: keep `pending` and the old key; `settlePendingRotation` asks the Worker next time.
            lastError = Self.syncError(for: error)
        case .http(let status, let code) where status == 409 && code == "stale_epoch":
            // The Worker is at a different epoch than this phone thinks. Look once; adopt the key only if it really is ours.
            if let state = try? await client.state(mirrorID: current.mirrorID, bearer: current.bearer), state.epoch == pending.epoch {
                promotePending()
                lastError = nil
            } else {
                discardPending()
                lastError = .other
            }
        case .http(let status, _) where status == 404:
            // The computer is already gone from the Worker, or this Worker has no rotation yet: revoke it the old way, without a new key.
            discardPending()
            do {
                try await client.removeDevice(mirrorID: current.mirrorID, bearer: current.bearer, deviceID: computerID)
            } catch let removal as MirrorClientError {
                guard case .http(let code, _) = removal, code == 404 else {
                    lastError = Self.syncError(for: removal)
                    return
                }
            } catch {
                lastError = .other
                return
            }
            current = stored ?? current
            current.computers.removeAll { $0.id == computerID }
            if secrets.save(current) { stored = current }
        default:
            discardPending()
            lastError = Self.syncError(for: error)
        }
    }

    /// If a rotation was started and its outcome is not known, asks the Worker which epoch it is at: the pending key becomes the
    /// key when the Worker took it, and is dropped when it did not. Returns false when the Worker could not be asked.
    private func settlePendingRotation() async -> Bool {
        guard let current = stored, let pending = current.pending else { return true }
        guard let origin = URL(string: current.origin) else { return false }
        do {
            let state = try await MirrorClient(origin: origin, session: session).state(mirrorID: current.mirrorID, bearer: current.bearer)
            if state.epoch == pending.epoch { promotePending() } else { discardPending() }
            return true
        } catch {
            lastError = Self.syncError(for: error)
            return false
        }
    }

    /// The Worker applied the rotation: the pending key is the key, the removed computers are gone, and everything is sent again.
    private func promotePending() {
        guard var current = stored, let pending = current.pending else { return }
        current.dataKey = pending.dataKey
        current.epoch = pending.epoch
        current.computers.removeAll { pending.removedIDs.contains($0.id) }
        current.pending = nil
        guard secrets.save(current) else { lastError = .other; return }
        stored = current
        index.reset()
        settingsValue.lastManifestAt = nil
        settingsValue.lastManifestIDsHash = nil
        settings.value = settingsValue
        lastAttemptAt = nil
    }

    private func discardPending() {
        guard var current = stored, current.pending != nil else { return }
        current.pending = nil
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
        case .http(let status, let code):
            if status == 401 || status == 403 { return .rejected }
            if status == 429 { return .rateLimited }
            if status == 409, code == "mirror_full" { return .full }
            return .other
        }
    }
}
