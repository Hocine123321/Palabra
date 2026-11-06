import XCTest

/// The scripted Books tour with the system in dark mode: lamp glow, the warm light and the dark page lighting.
final class BooksDarkTourUITests: BooksTourUITests {
    override var extraArguments: [String] { ["-UITestDark"] }
}
