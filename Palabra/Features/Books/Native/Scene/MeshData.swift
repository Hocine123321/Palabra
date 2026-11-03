import CoreGraphics
import Foundation
import SceneKit
import UIKit

/// SceneKit's texture space has v = 0 at the TOP of an image (the web scene's has v = 1 there). Every texture coordinate the
/// native scene makes goes through this, so the convention lives in one place.
enum TexCoord {
    static func v(_ webV: Double) -> Float { Float(1 - webV) }
}

/// Plain vertex data that becomes a `SCNGeometry`, so shapes can be built, mirrored and tested without a renderer.
struct MeshData {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    /// One index list per geometry element; element `i` uses material `i`.
    var elements: [[UInt32]] = []

    var triangleCount: Int { elements.reduce(0) { $0 + $1.count / 3 } }

    private static func source<T>(_ array: [T], _ semantic: SCNGeometrySource.Semantic, components: Int) -> SCNGeometrySource {
        let data = array.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(
            data: data, semantic: semantic, vectorCount: array.count, usesFloatComponents: true,
            componentsPerVector: components, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<T>.stride
        )
    }

    func geometry() -> SCNGeometry {
        var sources = [Self.source(positions, .vertex, components: 3), Self.source(normals, .normal, components: 3)]
        if !uvs.isEmpty { sources.append(Self.source(uvs, .texcoord, components: 2)) }
        let scnElements = elements.map { indices -> SCNGeometryElement in
            SCNGeometryElement(
                data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        return SCNGeometry(sources: sources, elements: scnElements)
    }

    /// The same mesh mirrored across the x = 0 plane (x and the normals' x negated, winding reversed so faces still point out).
    func mirroredInX() -> MeshData {
        var out = self
        out.positions = positions.map { SIMD3<Float>(-$0.x, $0.y, $0.z) }
        out.normals = normals.map { SIMD3<Float>(-$0.x, $0.y, $0.z) }
        out.elements = elements.map { Self.reversedWinding($0) }
        return out
    }

    static func reversedWinding(_ indices: [UInt32]) -> [UInt32] {
        var out = indices
        var i = 0
        while i + 2 < out.count {
            out.swapAt(i + 1, i + 2)
            i += 3
        }
        return out
    }

    // MARK: Shapes

    /// A box centred on the origin with three elements: 0 = the four sides, 1 = top (+y), 2 = bottom (-y).
    /// The top face's texture runs along +x in u and from the far edge (-z, image top) to the near edge in v.
    static func box(width w: Float, height h: Float, length l: Float) -> MeshData {
        var mesh = MeshData()
        mesh.elements = [[], [], []]
        let x = w / 2, y = h / 2, z = l / 2
        func quad(_ element: Int, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: [SIMD2<Float>]) {
            let base = UInt32(mesh.positions.count)
            mesh.positions += [a, b, c, d]
            mesh.normals += [n, n, n, n]
            mesh.uvs += uv
            // a, b, c, d go counter-clockwise seen from outside.
            mesh.elements[element] += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let standardUV: [SIMD2<Float>] = [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
        // Top: seen from +y with -z up the page: near-left, near-right, far-right, far-left.
        quad(1, SIMD3(-x, y, z), SIMD3(x, y, z), SIMD3(x, y, -z), SIMD3(-x, y, -z), SIMD3(0, 1, 0),
             [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)])
        // Bottom: seen from below.
        quad(2, SIMD3(-x, -y, -z), SIMD3(x, -y, -z), SIMD3(x, -y, z), SIMD3(-x, -y, z), SIMD3(0, -1, 0), standardUV)
        // Sides.
        quad(0, SIMD3(-x, -y, z), SIMD3(x, -y, z), SIMD3(x, y, z), SIMD3(-x, y, z), SIMD3(0, 0, 1), standardUV)
        quad(0, SIMD3(x, -y, -z), SIMD3(-x, -y, -z), SIMD3(-x, y, -z), SIMD3(x, y, -z), SIMD3(0, 0, -1), standardUV)
        quad(0, SIMD3(x, -y, z), SIMD3(x, -y, -z), SIMD3(x, y, -z), SIMD3(x, y, z), SIMD3(1, 0, 0), standardUV)
        quad(0, SIMD3(-x, -y, -z), SIMD3(-x, -y, z), SIMD3(-x, y, z), SIMD3(-x, y, -z), SIMD3(-1, 0, 0), standardUV)
        return mesh
    }

    /// A surface of revolution about the y axis. `profile` runs bottom to top as (radius, y); each segment keeps its own
    /// normal so caps and edges stay crisp while the surface stays smooth around.
    static func lathe(profile: [(r: Float, y: Float)], segments: Int) -> MeshData {
        var mesh = MeshData()
        var indices: [UInt32] = []
        for s in 0..<max(0, profile.count - 1) {
            let a = profile[s], b = profile[s + 1]
            let dr = b.r - a.r, dy = b.y - a.y
            let length = max((dr * dr + dy * dy).squareRoot(), 1e-6)
            let nr = dy / length, ny = -dr / length
            let base = UInt32(mesh.positions.count)
            for k in 0...segments {
                let t = Float(k) / Float(segments)
                let angle = 2 * Float.pi * t
                let c = cos(angle), sn = sin(angle)
                mesh.positions.append(SIMD3(a.r * c, a.y, a.r * sn))
                mesh.positions.append(SIMD3(b.r * c, b.y, b.r * sn))
                let normal = SIMD3<Float>(nr * c, ny, nr * sn)
                mesh.normals += [normal, normal]
                mesh.uvs += [SIMD2(t, 1), SIMD2(t, 0)]
            }
            for k in 0..<segments {
                let i = base + UInt32(k * 2)
                // a(k) = i, b(k) = i + 1, a(k+1) = i + 2, b(k+1) = i + 3.
                indices += [i, i + 1, i + 3, i, i + 3, i + 2]
            }
        }
        mesh.elements = [indices]
        return mesh
    }

    /// A flat disc facing up (+y) centred on the origin; uv runs 0...1 across it (u along +x, v along +z).
    static func disc(radius r: Float, segments: Int) -> MeshData {
        var mesh = MeshData()
        mesh.positions.append(SIMD3(0, 0, 0))
        mesh.normals.append(SIMD3(0, 1, 0))
        mesh.uvs.append(SIMD2(0.5, 0.5))
        var indices: [UInt32] = []
        for k in 0...segments {
            let a = 2 * Float.pi * Float(k) / Float(segments)
            let x = cos(a), z = sin(a)
            mesh.positions.append(SIMD3(r * x, 0, r * z))
            mesh.normals.append(SIMD3(0, 1, 0))
            mesh.uvs.append(SIMD2(0.5 + 0.5 * x, 0.5 + 0.5 * z))
        }
        for k in 0..<segments {
            // Counter-clockwise seen from above (+y): centre, next, current.
            indices += [0, UInt32(k + 2), UInt32(k + 1)]
        }
        mesh.elements = [indices]
        return mesh
    }

    /// A tube of radius `tube` following a circle arc of radius `radius` in the xy plane (centre at the origin), from angle
    /// `from` to `to` (radians). Used for the raised bands of a spine.
    static func tubeArc(radius: Float, tube: Float, from: Float, to: Float, arcSteps: Int, tubeSteps: Int) -> MeshData {
        var mesh = MeshData()
        for i in 0...arcSteps {
            let phi = from + (to - from) * Float(i) / Float(arcSteps)
            let radial = SIMD3<Float>(cos(phi), sin(phi), 0)
            let centre = radial * radius
            for j in 0...tubeSteps {
                let psi = 2 * Float.pi * Float(j) / Float(tubeSteps)
                let normal = radial * cos(psi) + SIMD3<Float>(0, 0, 1) * sin(psi)
                mesh.positions.append(centre + normal * tube)
                mesh.normals.append(normal)
                mesh.uvs.append(SIMD2(Float(i) / Float(arcSteps), Float(j) / Float(tubeSteps)))
            }
        }
        var indices: [UInt32] = []
        let row = UInt32(tubeSteps + 1)
        for i in 0..<arcSteps {
            for j in 0..<tubeSteps {
                let a = UInt32(i) * row + UInt32(j)
                indices += [a, a + row, a + 1, a + 1, a + row, a + row + 1]
            }
        }
        mesh.elements = [indices]
        return mesh
    }

    /// The half pipe that wraps the binding: bottom to top on the left (-x) side, centred on the origin, `length` along z.
    static func halfPipe(radius r: Float, length: Float, steps: Int) -> MeshData {
        var mesh = MeshData()
        for i in 0...steps {
            let theta = Float.pi + Float.pi * Float(i) / Float(steps)
            let x = r * sin(theta), y = -r * cos(theta)
            let normal = SIMD3<Float>(sin(theta), -cos(theta), 0)
            for (k, z) in [-length / 2, length / 2].enumerated() {
                mesh.positions.append(SIMD3(x, y, z))
                mesh.normals.append(normal)
                mesh.uvs.append(SIMD2(Float(i) / Float(steps), Float(k)))
            }
        }
        var indices: [UInt32] = []
        for i in 0..<steps {
            let a = UInt32(i * 2)
            indices += [a, a + 1, a + 3, a, a + 3, a + 2]
        }
        mesh.elements = [indices]
        return mesh
    }
}

/// Turns a grey height map into a tangent-space normal map (SceneKit has no bump slot).
enum NormalMapMaker {
    static func make(from height: CGImage, strength: Float) -> CGImage? {
        let w = height.width, h = height.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var source = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = source.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(height, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        func sample(_ x: Int, _ y: Int) -> Float {
            let cx = (x + w) % w, cy = (y + h) % h
            return Float(source[(cy * w + cx) * 4]) / 255
        }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (sample(x + 1, y) - sample(x - 1, y)) * strength
                let dy = (sample(x, y + 1) - sample(x, y - 1)) * strength
                let length = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * w + x) * 4
                out[i] = UInt8(max(0, min(255, (-dx / length * 0.5 + 0.5) * 255)))
                out[i + 1] = UInt8(max(0, min(255, (dy / length * 0.5 + 0.5) * 255)))
                out[i + 2] = UInt8(max(0, min(255, (1 / length * 0.5 + 0.5) * 255)))
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)
        guard let provider else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
