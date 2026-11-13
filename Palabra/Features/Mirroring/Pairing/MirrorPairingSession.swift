import CryptoKit
import Foundation
import Observation

/// One pairing, from a scanned link to "the computer has its keys". Nothing secret leaves the phone before the person
/// has compared the code with the computer's screen and tapped Confirm.
@MainActor
@Observable
final class MirrorPairingSession {
    enum Failure: Equatable {
        case slotTaken, expired, offline, alreadyPairedElsewhere, tooManyComputers, rateLimited, other
    }

    enum Phase: Equatable {
        case idle, joining
        case awaitingConfirmation(code: String)
        case finishing, done
        case failed(Failure)
        case cancelled
    }

    private(set) var phase: Phase = .idle

    private let link: PairingLink
    private let client: MirrorClient
    private let secrets: MirrorSecretsStore
    private let makeKey: () -> P256.KeyAgreement.PrivateKey
    private let randomBytes: (Int) -> Data
    private let now: () -> Date
    private var kPair: SymmetricKey?

    init(
        link: PairingLink,
        client: MirrorClient,
        secrets: MirrorSecretsStore,
        makeKey: @escaping () -> P256.KeyAgreement.PrivateKey = { P256.KeyAgreement.PrivateKey() },
        randomBytes: @escaping (Int) -> Data = MirrorCrypto.randomBytes,
        now: @escaping () -> Date = Date.init
    ) {
        self.link = link
        self.client = client
        self.secrets = secrets
        self.makeKey = makeKey
        self.randomBytes = randomBytes
        self.now = now
    }

    // MARK: Steps

    func start() async {
        guard phase == .idle else { return }
        if let existing = secrets.load(), existing.origin != link.origin.absoluteString {
            phase = .failed(.alreadyPairedElsewhere)
            return
        }
        phase = .joining
        let key = makeKey()
        let phonePublic = key.publicKey.x963Representation
        let agreed: SymmetricKey
        do {
            // Done before anything is sent: a link with a bad key reaches the network never.
            agreed = try MirrorCrypto.agree(privateKey: key, otherPublic: link.browserPublic, nonce: link.nonce)
        } catch {
            phase = .failed(.other)
            return
        }
        do {
            try await client.pairJoin(pairID: link.pairID, phonePublic: phonePublic)
        } catch {
            if phase == .joining { phase = .failed(Self.failure(for: error)) }
            return
        }
        guard phase == .joining else { return }
        kPair = agreed
        let code = MirrorCrypto.matchCode(browserPublic: link.browserPublic, phonePublic: phonePublic, nonce: link.nonce)
        phase = .awaitingConfirmation(code: code)
    }

    /// The person saw the same code on both screens. A second tap while this runs does nothing.
    func confirm() async {
        guard case .awaitingConfirmation = phase, let kPair else { return }
        phase = .finishing
        var addedDevice: (mirrorID: String, bearer: String, deviceID: String)?
        do {
            var stored = try await secretsForPairing()
            let deviceID = Base64URL.encode(randomBytes(16))
            let deviceToken = Base64URL.encode(randomBytes(32))
            try await client.addDevice(mirrorID: stored.mirrorID, bearer: stored.bearer, deviceID: deviceID, tokenHash: MirrorCrypto.sha256Hex(deviceToken))
            addedDevice = (stored.mirrorID, stored.bearer, deviceID)

            let deviceKey = Base64URL.encode(randomBytes(32))
            let wrap: [String: Any] = ["v": 1, "mirrorId": stored.mirrorID, "deviceId": deviceID, "deviceToken": deviceToken, "dataKey": stored.dataKey, "deviceKey": deviceKey]
            let sealed = try MirrorCrypto.sealWrap(key: kPair, pairID: link.pairID, plaintext: try JSONSerialization.data(withJSONObject: wrap))
            try await client.pairReply(pairID: link.pairID, sealed: sealed)

            stored.computers.append(MirrorComputer(id: deviceID, name: "Computer \(stored.computers.count + 1)", pairedAt: now(), deviceKey: deviceKey))
            guard secrets.save(stored) else { throw MirrorPairingError.couldNotSave }
            phase = .done
        } catch {
            if let added = addedDevice {
                // The computer never got its keys, so its access must not stay behind.
                try? await client.removeDevice(mirrorID: added.mirrorID, bearer: added.bearer, deviceID: added.deviceID)
            }
            phase = .failed(Self.failure(for: error))
        }
    }

    func cancel() async {
        switch phase {
        case .finishing, .done, .cancelled: return
        default: break
        }
        phase = .cancelled
        try? await client.pairCancel(pairID: link.pairID)
    }

    // MARK: Helpers

    private enum MirrorPairingError: Error { case couldNotSave }

    /// The stored secrets, or a new mirror on the Worker (saved before anything else uses it).
    private func secretsForPairing() async throws -> MirrorSecrets {
        if let existing = secrets.load() { return existing }
        let dataKey = Base64URL.encode(randomBytes(32))
        let ownerDeviceID = Base64URL.encode(randomBytes(16))
        let ownerToken = Base64URL.encode(randomBytes(32))
        let mirrorID = try await client.createMirror(deviceID: ownerDeviceID, ownerTokenHash: MirrorCrypto.sha256Hex(ownerToken))
        let created = MirrorSecrets(
            origin: link.origin.absoluteString, mirrorID: mirrorID, ownerDeviceID: ownerDeviceID,
            ownerToken: ownerToken, dataKey: dataKey, computers: []
        )
        guard secrets.save(created) else { throw MirrorPairingError.couldNotSave }
        return created
    }

    private static func failure(for error: Error) -> Failure {
        guard let client = error as? MirrorClientError else { return .other }
        switch client {
        case .offline: return .offline
        case .badResponse: return .other
        case .http(let status, let code):
            if status == 409 && code == "slot_taken" { return .slotTaken }
            if status == 409 && code == "too_many_devices" { return .tooManyComputers }
            if status == 404 || status == 410 { return .expired }
            if status == 429 { return .rateLimited }
            return .other
        }
    }
}
