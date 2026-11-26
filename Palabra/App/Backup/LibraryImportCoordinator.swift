import Foundation
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// The `.palabra` library file (declared in Info.plist through project.yml, so Files and the share sheet offer Palabra).
    static let palabraLibrary = UTType(exportedAs: "dev.palabra.library", conformingTo: .data)
}

enum LibraryImportOutcome: Equatable {
    case imported(LibraryBackupService.ImportSummary)
    case failed(LibraryBackupService.Failure)
    case unreadable
}

/// One place that imports a library file, whichever way it arrived: picked in Settings, or opened from Files / the
/// share sheet / AirDrop. The file is first copied into the app's own temporary folder (under the security scope and a
/// coordinated read, which also makes iCloud download it), so it is read from a stable local copy rather than from a
/// provider URL that can vanish or refuse a second read. Every attempt ends in an `outcome`, so a repeated import of
/// the same file is never silent: it runs again and reports what it found ("skipped" for what is already there).
@MainActor @Observable
final class LibraryImportCoordinator {
    private(set) var isImporting = false
    private(set) var outcome: LibraryImportOutcome?
    /// Bumps on every finished attempt, so a screen can tell "a new result" from "the one it already showed".
    private(set) var generation = 0

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Fire and forget (what the UI calls). An import already running is left to finish; the new request is dropped.
    func start(url: URL, makeService: @escaping @MainActor () -> LibraryBackupService) {
        guard !isImporting else { return }
        isImporting = true
        task = Task { [weak self] in
            await self?.run(url: url, makeService: makeService)
        }
    }

    /// The whole import; also what tests await.
    func run(url: URL, makeService: @MainActor () -> LibraryBackupService, stagingDirectory: URL = FileManager.default.temporaryDirectory) async {
        isImporting = true
        defer {
            isImporting = false
            generation += 1
        }
        let staged: URL
        do {
            // Off the main thread: the coordinated read waits for iCloud to download the file, and that wait must never
            // freeze the screen.
            staged = try await Task.detached(priority: .userInitiated) { try Self.stage(url, into: stagingDirectory) }.value
        } catch {
            outcome = .unreadable
            return
        }
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            outcome = .imported(try await makeService().importLibrary(from: staged))
        } catch let failure as LibraryBackupService.Failure {
            outcome = .failed(failure)
        } catch {
            outcome = .unreadable
        }
    }

    func clear() {
        outcome = nil
    }

    /// A private copy of the file, made while the picker's permission is open. `NSFileCoordinator` waits for an
    /// iCloud file to download and for a writer to finish.
    nonisolated static func stage(_ url: URL, into directory: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let target = directory.appendingPathComponent("import-\(UUID().uuidString).\(LibraryBackupService.fileExtension)")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: target) } catch { copyError = error }
        }
        if let failure = coordinationError ?? copyError { throw failure }
        return target
    }
}
