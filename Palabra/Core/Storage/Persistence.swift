import Foundation
import os
import SwiftData

enum PersistenceError: Error, Equatable {
    /// A batch of changes could not be written to the store (and was rolled back).
    case saveFailed
}

/// The one place a `ModelContext` is saved. A failed save used to disappear behind `try?`, so the screen showed
/// something saved that was not on disk. It is now logged (Console, subsystem `dev.palabra.app`) and reported
/// to the caller, which can react when it matters (an import count, removing a queue item).
enum Persistence {
    private static let log = Logger(subsystem: "dev.palabra.app", category: "persistence")

    @discardableResult
    static func save(_ context: ModelContext, file: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            log.error("Save failed at \(String(describing: file), privacy: .public):\(line): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
