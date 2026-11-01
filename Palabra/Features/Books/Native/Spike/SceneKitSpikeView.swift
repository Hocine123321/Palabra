import SwiftUI
import SceneKit

/// Throwaway rendering check for the native Books scene (plan Task 1): a lit, shadow-casting box on a floor with a
/// shader-modified material. It only shows when the app is launched with `-UITestSceneKitSpike`; it is deleted once the
/// real scene renders in CI.
struct SceneKitSpikeView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = Self.makeScene()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true
        view.accessibilityIdentifier = "sceneKitSpike"
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.9, alpha: 1)

        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .physicallyBased
        floorMaterial.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        floorMaterial.roughness.contents = 0.9
        floorMaterial.metalness.contents = 0.0
        floor.materials = [floorMaterial]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.08)
        let boxMaterial = SCNMaterial()
        boxMaterial.lightingModel = .physicallyBased
        boxMaterial.diffuse.contents = UIColor.systemOrange
        boxMaterial.roughness.contents = 0.4
        boxMaterial.metalness.contents = 0.0
        // Proves shader modifiers work: the box pulses between 50% and 100% brightness.
        boxMaterial.shaderModifiers = [.fragment: "_output.color.rgb *= 0.75 + 0.25 * sin(u_time * 2.0);"]
        box.materials = [boxMaterial]
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 0.5, 0)
        boxNode.castsShadow = true
        scene.rootNode.addChildNode(boxNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1600
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 4
        sun.shadowSampleCount = 8
        sun.shadowColor = UIColor(white: 0, alpha: 0.5)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.05
        camera.zFar = 40
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(3, 3, 5)
        let look = SCNLookAtConstraint(target: boxNode)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }
}
