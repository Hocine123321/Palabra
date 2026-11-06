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

    /// Keeps the sun's shadow on the active book.
    func aimShadow(at centre: SCNVector3) {
        sun.position = SCNVector3(centre.x - 3.4, 3.8, centre.z + 2.4)
        sun.look(at: centre)
    }

    private func apply() {
        let k = Self.lumensPerThree
        sun.light?.intensity = (dark ? 0.35 : 2.1) * k
        sun.light?.color = UIColor(rgb: dark ? 0x8aa0cc : 0xfff7ea)
        sun.light?.castsShadow = shadows
        // Hemisphere (0.42 / 0.16) plus the environment's share (0.55 / 0.22 of a bright room).
        fill.light?.intensity = (dark ? 0.16 + 0.22 : 0.42 + 0.55) * k * 0.55
        fill.light?.color = UIColor(rgb: dark ? 0x9fb0d0 : 0xfff3dd)
        lamp.light?.intensity = dark ? Self.lampLumens * lampScale : 0
        lamp.light?.castsShadow = dark && shadows
        lamp.isHidden = !dark
    }

    static func background(dark: Bool) -> UIColor { UIColor(rgb: dark ? 0x141311 : 0xe9e4d8) }
}
