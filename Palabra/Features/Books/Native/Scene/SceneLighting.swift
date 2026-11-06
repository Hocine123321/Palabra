import SceneKit
import UIKit

/// The lights of the desk (`app.js` _boot / setAppearance): a sun, a soft ambient fill that stands in for the web scene's
/// hemisphere light and room environment, and a warm lamp spot in dark mode. Values are the Three.js intensities divided by
/// pi and scaled to SceneKit lumens, then tuned against footage.
@MainActor
final class SceneLighting {
    let root = SCNNode()
    private let sun = SCNNode()
    private let fill = SCNNode()
    private let lamp = SCNNode()
    private(set) var dark = false
    private(set) var shadows = true
    /// How much of the window's daylight shows (0...1; light mode, on the desk): a lower, warmer sun that the window bars can
    /// shadow. It eases with the window's fade, so the sun glides between its two places and nothing pops.
    private(set) var windowAmount = 0.0
    /// A slow drift applied to the lamp's strength (1 = none).
    private(set) var lampScale = 1.0

    /// SceneKit lumens that correspond to a Three.js intensity of 1 on the same light.
    static let lumensPerThree = 1000.0 / Double.pi
    /// The dark-mode lamp. The Three.js value (34 x 4 x pi-scaled = 4300) blows the page out in SceneKit; 70 reads like a warm desk
    /// lamp (picked from exposure footage at 25 to 1800: 50 is moody, 80 starts to yellow the paper).
    static let lampLumens = 70.0

    init() {
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.castsShadow = true
        sunLight.shadowMode = .forward
        sunLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunLight.shadowRadius = 4
        sunLight.shadowSampleCount = 8
        sunLight.shadowBias = 0.4
        sunLight.orthographicScale = 3.4
        sunLight.zNear = 1
        sunLight.zFar = 14
        sunLight.shadowColor = UIColor(white: 0, alpha: 0.55)
        sun.light = sunLight
        sun.position = SCNVector3(-3.4, 3.8, 2.4)
        sun.look(at: SCNVector3Zero)
        root.addChildNode(sun)

        let ambient = SCNLight()
        ambient.type = .ambient
        fill.light = ambient
        root.addChildNode(fill)

        let spot = SCNLight()
        spot.type = .spot
        spot.spotInnerAngle = 30
        spot.spotOuterAngle = 49
        spot.attenuationStartDistance = 0
        spot.attenuationEndDistance = 12
        spot.attenuationFalloffExponent = 1.6
        spot.color = UIColor(rgb: 0xffc880)
        spot.castsShadow = true
        spot.shadowMode = .forward
        spot.shadowMapSize = CGSize(width: 2048, height: 2048)
        spot.shadowRadius = 5
        spot.shadowSampleCount = 8
        spot.zNear = 0.5
        spot.zFar = 12
        lamp.light = spot
        lamp.position = SCNVector3(-1.4, 3.4, -1.6)
        lamp.look(at: SCNVector3Zero)
        root.addChildNode(lamp)
        apply()
    }

    func setAppearance(dark: Bool) {
        self.dark = dark
        placeSun()
        apply()
    }

    func setLampScale(_ scale: Double) {
        guard abs(scale - lampScale) > 1e-4 else { return }
        lampScale = scale
        apply()
    }

    func setShadows(_ enabled: Bool) {
        shadows = enabled
        apply()
    }

    /// Where the sun's shadow is aimed (the desk centre unless `aimShadow` says otherwise).
    private var aimed = SCNVector3Zero

    /// Keeps the sun's shadow on the active book.
    func aimShadow(at centre: SCNVector3) {
        aimed = centre
        placeSun()
    }

    func setWindowAmount(_ amount: Double) {
        let next = min(1, max(0, amount))
        guard abs(next - windowAmount) > 1e-3 else { return }
        windowAmount = next
        placeSun()
        apply()
    }

    private func placeSun() {
        let plain = SCNVector3(aimed.x - 3.4, 3.8, aimed.z + 2.4)
        let window = WindowLight.sunPosition(centre: aimed)
        let k = Float(dark ? 0 : windowAmount)
        sun.position = SCNVector3(
            plain.x + (window.x - plain.x) * k, plain.y + (window.y - plain.y) * k, plain.z + (window.z - plain.z) * k
        )
        sun.look(at: aimed)
    }

    private func apply() {
        let k = Self.lumensPerThree
        // With the window lit the sun is the star of the room: stronger, golden, and the fill turns cool and soft so the
        // bars' shadows read blue-ish, the way they do in daylight.
        let day = dark ? 0 : windowAmount
        sun.light?.intensity = (dark ? 0.35 : 2.1 + 0.6 * day) * k
        sun.light?.color = dark ? UIColor(rgb: 0x8aa0cc) : Self.mix(0xfff7ea, 0xffe9c2, day)
        sun.light?.shadowColor = UIColor(red: 0.10, green: 0.14, blue: 0.24, alpha: dark ? 0.55 : 0.55 + 0.07 * day)
        sun.light?.castsShadow = shadows
        // Hemisphere (0.42 / 0.16) plus the environment's share (0.55 / 0.22 of a bright room).
        fill.light?.intensity = (dark ? 0.16 + 0.22 : 0.42 + 0.55 - 0.18 * day) * k * 0.55
        fill.light?.color = dark ? UIColor(rgb: 0x9fb0d0) : Self.mix(0xfff3dd, 0xdce8ff, day)
        lamp.light?.intensity = dark ? Self.lampLumens * lampScale : 0
        lamp.light?.castsShadow = dark && shadows
        lamp.isHidden = !dark
    }

    /// Blends two colours (`t` 0 = `a`, 1 = `b`).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UIColor {
        func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
        func lerp(_ shift: UInt32) -> CGFloat { CGFloat(channel(a, shift) + (channel(b, shift) - channel(a, shift)) * t) }
        return UIColor(red: lerp(16), green: lerp(8), blue: lerp(0), alpha: 1)
    }

    /// Behind the desk. Light mode is a warm gradient, bright where the window is and settling into a soft shade, so the room has
    /// depth instead of one flat beige; dark mode stays near-black.
    static func background(dark: Bool) -> Any {
        dark ? UIColor(rgb: 0x141311) : lightBackground
    }

    private static let lightBackground: UIImage = {
        let size = CGSize(width: 64, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(rgb: 0xf6e7c8).cgColor, UIColor(rgb: 0xe9dcc2).cgColor, UIColor(rgb: 0xcdbf9f).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }()
}
