import Foundation

/// The active provider and the backup keys, readable from any thread. The retry layer asks for the backup key from
/// background tasks, so it cannot go through the main-actor `AppEnvironment`.
final class ProviderState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AIProvider
    private let backupKeychains: [AIProvider: KeychainStore]

    init(active: AIProvider, backupKeychains: [AIProvider: KeychainStore]) {
        current = active
        self.backupKeychains = backupKeychains
    }

    var active: AIProvider {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }

    func backupKey() -> String? { backupKeychains[active]?.read() }
}
