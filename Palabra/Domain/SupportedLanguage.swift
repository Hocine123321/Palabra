import Foundation
import SwiftUI

/// The two languages supported independently by the app interface and AI output.
enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case arabic = "ar"

    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    var instructionName: String {
        self == .arabic ? "Arabic" : "English"
    }
}
