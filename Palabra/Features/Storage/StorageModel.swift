import Foundation
import Observation

/// State of one folder in the Storage browser: the rows, the clipboard, and the last error.
@MainActor
@Observable
final class StorageFolderModel {
    let browser: StorageBrowser
    let folder: URL

    private(set) var items: [StorageItem] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    var errorMessage: String?

    init(browser: StorageBrowser, folder: URL) {
        self.browser = browser
        self.folder = folder
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    func reload() async {
        isLoading = true
        let browser = browser, folder = folder
        let result: Result<[StorageItem], StorageError> = await Task.detached(priority: .userInitiated) {
            do { return .success(try browser.list(folder)) } catch { return .failure(error as? StorageError ?? .failed("")) }
        }.value
        isLoading = false
        switch result {
        case .success(let list): items = list; loadFailed = false
        case .failure: items = []; loadFailed = true
        }
    }

    /// Runs a file change off the main thread, reports its error, then reloads. Returns whether it worked.
    @discardableResult
    func perform(_ work: @escaping @Sendable (StorageBrowser) throws -> Void) async -> Bool {
        let browser = browser
        let error: StorageError? = await Task.detached(priority: .userInitiated) {
            do { try work(browser); return nil } catch { return error as? StorageError ?? .failed("") }
        }.value
        errorMessage = error?.message
        await reload()
        return error == nil
    }

    func delete(_ item: StorageItem) async { await perform { try $0.delete(item.url) } }
    func rename(_ item: StorageItem, to name: String) async { await perform { try $0.rename(item.url, to: name) } }
    func createFolder(named name: String) async { let folder = folder; await perform { try $0.createFolder(named: name, in: folder) } }
    func paste(_ source: URL) async { await paste(source, into: folder) }
    func paste(_ source: URL, into destination: URL) async { await perform { _ = try $0.copy(source, into: destination) } }
    func importFile(_ url: URL) async { let folder = folder; await perform { _ = try $0.importFile(from: url, into: folder) } }
}

/// What "Copy" put aside, shared by every folder screen so it can be pasted into another one.
@MainActor
@Observable
final class StorageClipboard {
    private(set) var source: URL?
    var hasItem: Bool { source != nil }
    var name: String { source?.lastPathComponent ?? "" }
    func copy(_ url: URL) { source = url }
    func clear() { source = nil }
}

/// Totals for the overview card.
struct StorageUsage: Equatable, Sendable {
    var root: StorageRoot
    var bytes: Int64
}

enum StorageOverview {
    static func measure() async -> [StorageUsage] {
        await Task.detached(priority: .utility) {
            StorageRoot.allCases.map { root in
                StorageUsage(root: root, bytes: StorageBrowser(root: root.url()).totalSize(of: root.url()))
            }
        }.value
    }
}
