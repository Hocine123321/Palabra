import CoreGraphics
import Foundation

/// Port of the textures of desk.js: the wooden planks and the felt mat.
enum DeskArt {
    /// Colour and height maps of four planks; the scene repeats them 3 x 3.4 over the desk.
    static func wood() -> (map: CGImage, bump: CGImage) {
        let size = 1024
        let W = Double(size), H = Double(size)
        let c = PixelCanvas(width: size, height: size)
        let b = PixelCanvas(width: size, height: size)
        var r = SeededRandom(seed: 42)
        let planks = 4
        let plankW = W / Double(planks)
        for p in 0..<planks {
            let x0 = Double(p) * plankW
            let tone = 0.9 + r.next() * 0.2
            c.fillStyle(PageColor(red: (196 * tone).rounded(), green: (150 * tone).rounded(), blue: (104 * tone).rounded(), alpha: 1))
            c.fillRect(x0, 0, plankW, H)
            for _ in 0..<90 {
                let x = x0 + r.next() * plankW
                let a = 0.03 + r.next() * 0.08
                c.strokeStyle(r.next() > 0.5 ? PageColor(red: 90, green: 50, blue: 20, alpha: a) : PageColor(red: 255, green: 225, blue: 180, alpha: a * 0.7))
                let lineWidth = 1 + r.next() * 2.2
                c.ctx.move(to: CGPoint(x: x, y: 0))
                var yy = 0.0
                var xx = x
                while yy < H {
                    yy += 40
                    xx += (r.next() - 0.5) * 5
                    c.ctx.addLine(to: CGPoint(x: xx, y: yy))
                }
                c.strokeCurrentPath(width: lineWidth)
            }
            c.fillStyle("rgba(40,20,5,0.55)")
            c.fillRect(x0, 0, 3, H)
        }
        b.fillStyle("#808080")
        b.fillRect(0, 0, W, H)
        for _ in 0..<700 {
            b.strokeStyle(r.next() > 0.5 ? "rgba(0,0,0,0.25)" : "rgba(255,255,255,0.25)")
            let x = r.next() * W
            b.line(x, 0, x + (r.next() - 0.5) * 10, H)
            b.strokeCurrentPath(width: 1)
        }
        b.fillStyle("rgba(0,0,0,0.9)")
        for p in 0..<planks { b.fillRect(Double(p) * plankW, 0, 4, H) }
        return (c.image(), b.image())
    }

    /// A white tile with faint speckle; tinted by the material colour and repeated 6 x 6.
    static func felt() -> CGImage {
        let c = PixelCanvas(width: 256, height: 256)
        var r = SeededRandom(seed: 5)
        c.fillStyle("#ffffff")
        c.fillRect(0, 0, 256, 256)
        for _ in 0..<6000 {
            c.ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: CGFloat(r.next() * 0.08)))
            let x = r.next() * 256
            let y = r.next() * 256
            c.fillRect(x, y, 1.5, 1.5)
        }
        return c.image()
    }
}
