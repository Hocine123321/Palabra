import XCTest
import UIKit

/// A scripted walk through the Books tab, the way a person reviewing the app would do it. It asserts almost nothing: its job
/// is to leave evidence. CI records the simulator screen while it runs and publishes the video, one JPEG per step and
/// `steps.json` (what was tried, whether the control was there, when) on the `ci-recordings` branch.
/// Not part of the normal UI test run (see the workflow); run it on its own with `-only-testing:PalabraUITests/BooksTourUITests`.
final class BooksTourUITests: XCTestCase {
    private struct Step: Encodable {
        var n: Int
        var name: String
        var t: Double
        var ok: Bool
        var note: String
    }

    private var steps: [Step] = []
    private var started = Date()
    private var outputDirectory: URL?

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        started = Date()
        if let path = ProcessInfo.processInfo.environment["TOUR_DIR"], !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: outputDirectory!, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        if let outputDirectory, let data = try? JSONEncoder().encode(steps) {
            try? data.write(to: outputDirectory.appendingPathComponent("steps.json"))
        }
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: Helpers

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Writes a half-size JPEG named after the step, and records the step.
    private func record(_ name: String, ok: Bool = true, note: String = "") {
        let n = steps.count + 1
        steps.append(Step(n: n, name: name, t: Date().timeIntervalSince(started), ok: ok, note: note))
        guard let outputDirectory else { return }
        let image = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale * 0.5, height: image.size.height * image.scale * 0.5)
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        if let data = small.jpegData(compressionQuality: 0.72) {
            let file = String(format: "%02d-%@.jpg", n, name)
            try? data.write(to: outputDirectory.appendingPathComponent(file))
        }
    }

    /// Taps a control if it is there; either way the step is recorded with a picture.
    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, step: String, wait: Double = 1.2, timeout: Double = 6) -> Bool {
        let target = element(app, id)
        let found = target.waitForExistence(timeout: timeout)
        if found { target.tap() }
        pause(wait)
        record(step, ok: found, note: found ? "" : "control \(id) not found")
        return found
    }

    // MARK: The tour

    func testBooksTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Books"].tap()
        _ = element(app, "bookCover.history").waitForExistence(timeout: 10)
        _ = element(app, "booksLoading").waitForNonExistence(timeout: 40)
        pause(2.5)
        record("menu-portrait")

        // Open History and look at the first pages.
        tap(app, "bookCover.history", step: "open-history", wait: 4)
        pause(2)
        record("page-1")
        tap(app, "pageNext", step: "page-2", wait: 2.5)
        tap(app, "pageNext", step: "page-3", wait: 2.5)
        tap(app, "pagePrevious", step: "back-to-page-2", wait: 2.5)

        // Tools in hand.
        tap(app, "toolLens", step: "magnifier-in-hand", wait: 2.5)
        tap(app, "toolLens", step: "magnifier-put-away", wait: 2)
        tap(app, "toolRuler", step: "ruler-in-hand", wait: 2.5)
        tap(app, "toolRuler", step: "ruler-put-away", wait: 2)
        tap(app, "toolBookmark", step: "bookmark-in-hand", wait: 2.5)
        tap(app, "toolBookmark", step: "bookmark-put-away", wait: 2)

        // Memorize: hide answers, change level, reveal, magnifier over hidden answers.
        tap(app, "recallToggle", step: "memorize-on", wait: 2.5)
        tap(app, "toolLens", step: "memorize-with-magnifier", wait: 2.5)
        tap(app, "toolLens", step: "memorize-magnifier-away", wait: 1.5)
        let level = element(app, "recallLevel")
        if level.waitForExistence(timeout: 3) {
            let buttons = level.buttons
            if buttons.count >= 2 { buttons.element(boundBy: 1).tap() }
            pause(1.5)
            record("memorize-key-facts")
        } else {
            record("memorize-key-facts", ok: false, note: "level picker not found")
        }
        tap(app, "recallReveal", step: "memorize-reveal-page", wait: 1.5)
        tap(app, "recallToggle", step: "memorize-off", wait: 2)

        // Text size.
        if tap(app, "textSizeMenu", step: "text-size-menu", wait: 1) {
            let larger = app.buttons["Larger"].firstMatch
            if larger.waitForExistence(timeout: 3) { larger.tap() }
            pause(3)
            record("text-size-larger")
        }

        // Focus Mode.
        tap(app, "focusButton", step: "focus-mode", wait: 3)
        tap(app, "focusExit", step: "focus-exit", wait: 2.5)

        // Landscape.
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(3.5)
        record("reading-landscape")
        app.swipeUp()
        pause(1.5)
        record("reading-landscape-scrolled")
        tap(app, "pageNext", step: "landscape-next-page", wait: 3)
        tap(app, "bookBack", step: "landscape-back-to-menu", wait: 4)
        record("menu-landscape")
        XCUIDevice.shared.orientation = .portrait
        pause(3)
        record("menu-portrait-again")

        // Geography is empty; Read as text; then Settings.
        tap(app, "bookCover.geography", step: "geography-empty", wait: 1.5)
        tap(app, "bookCover.history", step: "reopen-history", wait: 4)
        tap(app, "bookBack", step: "close-book", wait: 4)

        app.tabBars.buttons["Settings"].tap()
        let link = element(app, "booksSettingsLink")
        var scrolls = 0
        while !link.waitForExistence(timeout: 1.5), scrolls < 8 { app.swipeUp(); scrolls += 1 }
        pause(0.8)
        record("settings-list", ok: link.exists)
        if link.exists {
            link.tap()
            pause(1.5)
            record("books-settings")
        }
    }
}
