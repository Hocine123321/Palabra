import XCTest

/// The same scripted tour, with the native SceneKit desk. Run on its own: `-only-testing:PalabraUITests/NativeBooksTourUITests`.
final class NativeBooksTourUITests: BooksTourUITests {
    override var extraArguments: [String] { ["-UITestNativeBooks"] }
}
