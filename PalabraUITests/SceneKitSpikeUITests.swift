import XCTest
import UIKit

/// Throwaway: shows that SceneKit draws in the CI simulator (lit box, shadow, shader modifier). Not part of the normal
/// run; start it with the workflow's review job (`review_test=PalabraUITests/SceneKitSpikeUITests`).
final class SceneKitSpikeUITests: XCTestCase {
    func testRenders() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestSceneKitSpike"]
        app.launch()
        let spike = app.descendants(matching: .any).matching(identifier: "sceneKitSpike").firstMatch
        XCTAssertTrue(spike.waitForExistence(timeout: 15), "the spike view did not appear")
        Thread.sleep(forTimeInterval: 2)
        let first = XCUIScreen.main.screenshot()
        Thread.sleep(forTimeInterval: 0.9)
        let second = XCUIScreen.main.screenshot()
        save(first, name: "spike-a")
        save(second, name: "spike-b")
        XCTAssertNotEqual(first.pngRepresentation, second.pngRepresentation, "nothing moved: the shader modifier or the view is not running")
        let stats = luminanceStats(first.image)
        XCTAssertGreaterThan(stats.spread, 0.05, "the frame is flat (black or one colour): SceneKit probably did not draw")
    }

    private func save(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let path = ProcessInfo.processInfo.environment["REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = shot.image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: directory.appendingPathComponent("\(name).jpg"))
        }
    }

    /// Mean luminance and the spread between the 5th and 95th percentile of a 64x64 downsample.
    private func luminanceStats(_ image: UIImage) -> (mean: Double, spread: Double) {
        let side = 64
        guard let cg = image.cgImage,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return (0, 0) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var values: [Double] = []
        for i in 0..<(side * side) {
            let r = Double(bytes[i * 4]), g = Double(bytes[i * 4 + 1]), b = Double(bytes[i * 4 + 2])
            values.append((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255)
        }
        values.sort()
        let mean = values.reduce(0, +) / Double(values.count)
        let low = values[values.count / 20], high = values[values.count * 19 / 20]
        return (mean, high - low)
    }
}
