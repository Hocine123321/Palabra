import XCTest

/// The native tour with the system in dark mode: lamp glow, the warm light and the dark page lighting.
final class NativeBooksDarkTourUITests: BooksTourUITests {
    override var extraArguments: [String] { ["-UITestNativeBooks", "-AppleInterfaceStyle", "Dark"] }
}
