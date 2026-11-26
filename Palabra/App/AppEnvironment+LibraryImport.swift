import Foundation

extension AppEnvironment {
    /// Imports a `.palabra` file however it reached the app (the Settings picker, or opened from Files / share sheet).
    func importLibraryFile(_ url: URL) {
        libraryImport.start(url: url, makeService: { [unowned self] in makeBackupService() })
    }

    /// An opened file: show where the result appears, then import.
    func openLibraryFile(_ url: URL) {
        router.tab = .settings
        importLibraryFile(url)
    }
}
