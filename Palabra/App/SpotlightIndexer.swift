import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Lets iOS search find the person's words (title: the word, description: its meaning). Everything stays on the
/// phone: this only fills the system's local search index. Tapping a result opens the word (see `RootView`).
@MainActor
enum SpotlightIndexer {
    static let domain = "dev.palabra.app.words"
    /// A cap, so a huge library never makes the index a burden.
    static let maxItems = 5000

    /// Replaces everything this app put in the index with the current library.
    static func reindex(_ summaries: [WordSummary]) {
        let items = summaries.prefix(maxItems).map { summary -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = summary.spanish
            attributes.contentDescription = summary.translation
            attributes.keywords = [summary.spanish, summary.translation].filter { !$0.isEmpty }
            return CSSearchableItem(uniqueIdentifier: summary.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// The word a tapped Spotlight result stands for.
    static func wordID(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap { UUID(uuidString: $0) }
    }
}
