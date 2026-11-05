import XCTest
import UIKit

/// Evidence for tuning the dark-mode lamp: launches the native desk at several lamp strengths and photographs the menu and a page.
final class NativeDarkExposureUITests: XCTestCase {
    private func save(_ name: String) {
        guard let path = ProcessInfo.processInfo.environment["REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale * 0.5, height: image.size.height * image.scale * 0.5)
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.jpegData(compressionQuality: 0.72)?.write(to: directory.appendingPathComponent("\(name).jpg"))
    }

    func testLampStrengths() {
        for lumens in [150, 400, 900, 1800] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestNativeBooks", "-UITestDark", "-UITestLampLumens", "\(lumens)"]
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            app.tabBars.buttons["Books"].tap()
            let cover = app.descendants(matching: .any).matching(identifier: "bookCover.history").firstMatch
            _ = cover.waitForExistence(timeout: 12)
            Thread.sleep(forTimeInterval: 3)
            save("lamp\(lumens)-menu")
            if cover.exists { cover.tap() }
            Thread.sleep(forTimeInterval: 5)
            save("lamp\(lumens)-page")
            app.terminate()
        }
    }
}
