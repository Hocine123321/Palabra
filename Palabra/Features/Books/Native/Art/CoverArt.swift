import CoreGraphics
import CoreText
import Foundation

/// The maps of one book cover. Roughness and metalness are separate grey maps (the web scene packed them into one image).
struct CoverTextures {
    var color: CGImage
    var roughness: CGImage
    var metalness: CGImage
    /// A height map of the grain or weave; the scene turns it into a normal map.
    var bump: CGImage
    var endpaper: CGImage
    /// Colours of the cloth edge and the cloth on the spine and back.
    var edge: PageColor
    var cloth: PageColor
}

/// Port of cover.js: procedural cloth covers with gold foil, and the striped edge of the page block.
enum CoverArt {
    static let width = 1024
    static let height = 1450
    private static let W = Double(width)
    private static let H = Double(height)

    private static func font(_ size: Double) -> CTFont { PageFonts.ctFont(FontSpec(size: size, bold: true)) }

    private struct Layers {
        let color = PixelCanvas(width: CoverArt.width, height: CoverArt.height)
        let roughness = PixelCanvas(width: CoverArt.width, height: CoverArt.height)
        let metalness = PixelCanvas(width: CoverArt.width, height: CoverArt.height)
        let bump = PixelCanvas(width: CoverArt.width, height: CoverArt.height)
    }

    private static func frame(_ c: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double, _ lw: Double) {
        c.roundRectPath(x, y, w, h, r)
        c.strokeCurrentPath(width: lw)
    }

    /// Gold foil drawn into the colour map (as a gradient), the roughness map (shiny) and the metalness map (metal).
    private static func foil(_ layers: Layers, _ draw: (PixelCanvas) -> Void) {
        let g = layers.color.ctx
        g.saveGState()
        g.beginTransparencyLayer(auxiliaryInfo: nil)
        layers.color.fillStyle(PageColor(r: 0, g: 0, b: 0))
        layers.color.strokeStyle(PageColor(r: 0, g: 0, b: 0))
        draw(layers.color)
        g.setBlendMode(.sourceIn)
        layers.color.fillRectWithGradient(
            CGRect(x: 0, y: 0, width: W, height: H), from: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: H),
            stops: [(0, PixelCanvas.css("#f6d27a")), (0.5, PixelCanvas.css("#c8962e")), (1, PixelCanvas.css("#f1c765"))]
        )
        g.endTransparencyLayer()
        g.restoreGState()

        for (canvas, value) in [(layers.roughness, 60.0), (layers.metalness, 255.0)] {
            canvas.ctx.saveGState()
            canvas.fillStyle(canvas.gray(value))
            canvas.strokeStyle(canvas.gray(value))
            draw(canvas)
            canvas.ctx.restoreGState()
        }
    }

    private static func historyCover() -> CoverTextures {
        let L = Layers()
        let g = L.color
        g.fillRectWithGradient(
            CGRect(x: 0, y: 0, width: W, height: H), from: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: H),
            stops: [(0, PixelCanvas.css("#8f2a37")), (0.55, PixelCanvas.css("#6b1a25")), (1, PixelCanvas.css("#4a111a"))]
        )
        g.grain(width: W, height: H, seed: 11, dots: 26000, darkAlpha: 0.10, lightAlpha: 0.05)
        L.roughness.fillStyle(L.roughness.gray(170))
        L.roughness.fillRect(0, 0, W, H)
        L.metalness.fillStyle(L.metalness.gray(0))
        L.metalness.fillRect(0, 0, W, H)
        L.bump.fillStyle("#808080")
        L.bump.fillRect(0, 0, W, H)
        L.bump.grain(width: W, height: H, seed: 5, dots: 40000, darkAlpha: 0.35, lightAlpha: 0.35)

        foil(L) { c in
            let g = c.ctx
            g.setLineJoin(.round)
            frame(c, 78, 78, W - 156, H - 156, 20, 9)
            frame(c, 100, 100, W - 200, H - 200, 12, 3)
            // corner ornaments
            let corners: [(Double, Double, Double, Double)] = [
                (130, 130, 1, 1), (W - 130, 130, -1, 1), (130, H - 130, 1, -1), (W - 130, H - 130, -1, -1)
            ]
            for (cx, cy, sx, sy) in corners {
                g.saveGState()
                g.translateBy(x: CGFloat(cx), y: CGFloat(cy))
                g.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
                g.move(to: CGPoint(x: 0, y: 90))
                g.addQuadCurve(to: CGPoint(x: 90, y: 0), control: CGPoint(x: 0, y: 0))
                c.strokeCurrentPath(width: 5)
                c.circlePath(34, 34, 12)
                c.fillCurrentPath()
                g.restoreGState()
            }
            // medallion
            c.circlePath(W / 2, 480, 190)
            c.strokeCurrentPath(width: 6)
            c.circlePath(W / 2, 480, 168)
            c.strokeCurrentPath(width: 2)
            g.saveGState()
            g.translateBy(x: CGFloat(W / 2), y: 480)
            // a columned portico
            g.move(to: CGPoint(x: -110, y: -70))
            g.addLine(to: CGPoint(x: 0, y: -130))
            g.addLine(to: CGPoint(x: 110, y: -70))
            g.closePath()
            c.strokeCurrentPath(width: 5)
            c.fillRect(-120, -64, 240, 14)
            for i in -3...3 { c.fillRect(Double(i) * 34 - 8, -42, 16, 100) }
            c.fillRect(-124, 62, 248, 14)
            c.fillRect(-140, 80, 280, 10)
            g.restoreGState()
            c.text("التاريخ", font: font(190), x: W / 2, baseline: 920, align: .center)
            c.text("H I S T O R Y", font: font(52), x: W / 2, baseline: 1130, align: .center)
            c.line(W / 2 - 220, 1185, W / 2 + 220, 1185)
            c.strokeCurrentPath(width: 3)
            c.circlePath(W / 2, 1185, 9)
            c.fillCurrentPath()
        }
        return CoverTextures(
            color: L.color.image(), roughness: L.roughness.image(), metalness: L.metalness.image(), bump: L.bump.image(),
            endpaper: endpaper(subject: "history"), edge: PixelCanvas.css("#4a111a"), cloth: PixelCanvas.css("#5a1621")
        )
    }

    private static func geographyCover() -> CoverTextures {
        let L = Layers()
        let g = L.color
        g.fillRectWithGradient(
            CGRect(x: 0, y: 0, width: W, height: H), from: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: H),
            stops: [(0, PixelCanvas.css("#2a8a96")), (0.6, PixelCanvas.css("#15616c")), (1, PixelCanvas.css("#0c4049"))]
        )
        // buckram weave
        g.strokeStyle("rgba(255,255,255,0.045)")
        for x in stride(from: 0, to: width, by: 4) {
            g.line(Double(x), 0, Double(x), H)
            g.strokeCurrentPath(width: 1)
        }
        g.strokeStyle("rgba(0,0,0,0.07)")
        for y in stride(from: 0, to: height, by: 4) {
            g.line(0, Double(y), W, Double(y))
            g.strokeCurrentPath(width: 1)
        }
        g.grain(width: W, height: H, seed: 23, dots: 14000, darkAlpha: 0.07, lightAlpha: 0.05)
        L.roughness.fillStyle(L.roughness.gray(215))
        L.roughness.fillRect(0, 0, W, H)
        L.metalness.fillStyle(L.metalness.gray(0))
        L.metalness.fillRect(0, 0, W, H)
        let b = L.bump
        b.fillStyle("#808080")
        b.fillRect(0, 0, W, H)
        b.strokeStyle("rgba(0,0,0,0.5)")
        for x in stride(from: 0, to: width, by: 4) {
            b.line(Double(x), 0, Double(x), H)
            b.strokeCurrentPath(width: 1)
        }
        b.strokeStyle("rgba(255,255,255,0.5)")
        for y in stride(from: 0, to: height, by: 4) {
            b.line(0, Double(y), W, Double(y))
            b.strokeCurrentPath(width: 1)
        }

        // printed cream cartography
        let ink = "rgba(244,238,214,0.9)"
        let c = g.ctx
        c.saveGState()
        c.translateBy(x: CGFloat(W / 2), y: 600)
        g.strokeStyle(ink)
        var r = 120.0
        while r <= 380 {
            c.setAlpha(CGFloat(0.9 - r / 600))
            g.circlePath(0, 0, r)
            g.strokeCurrentPath(width: 3)
            r += 65
        }
        c.setAlpha(0.55)
        for a in 0..<12 {
            let angle = Double(a) * Double.pi / 12
            c.saveGState()
            c.rotate(by: CGFloat(angle))
            let rx = 380 * abs(cos(angle + 0.01)) + 6
            c.addEllipse(in: CGRect(x: -rx, y: -380, width: 2 * rx, height: 760))
            g.strokeCurrentPath(width: 3)
            c.restoreGState()
        }
        c.setAlpha(1)
        g.line(-380, 0, 380, 0)
        g.strokeCurrentPath(width: 7)
        // compass rose
        g.fillStyle(ink)
        for i in 0..<4 {
            c.saveGState()
            c.rotate(by: CGFloat(Double(i) * Double.pi / 2))
            c.move(to: CGPoint(x: 0, y: -150))
            c.addLine(to: CGPoint(x: 16, y: -16))
            c.addLine(to: CGPoint(x: -16, y: -16))
            c.closePath()
            c.fillPath()
            c.restoreGState()
        }
        c.restoreGState()
        g.fillStyle("rgba(244,238,214,0.95)")
        g.strokeStyle("rgba(244,238,214,0.95)")
        frame(g, 72, 72, W - 144, H - 144, 8, 5)

        foil(L) { c in
            c.text("الجغرافيا", font: font(200), x: W / 2, baseline: 1150, align: .center)
            c.text("A T L A S", font: font(54), x: W / 2, baseline: 1250, align: .center)
            c.line(W / 2 - 160, 1290, W / 2 + 160, 1290)
            c.strokeCurrentPath(width: 4)
        }
        return CoverTextures(
            color: L.color.image(), roughness: L.roughness.image(), metalness: L.metalness.image(), bump: L.bump.image(),
            endpaper: endpaper(subject: "geography"), edge: PixelCanvas.css("#0c3a42"), cloth: PixelCanvas.css("#12525d")
        )
    }

    /// Plain material for the endpaper, back cover, and cloth edges (tiles; the scene repeats it 2 x 3).
    static func endpaper(subject: String) -> CGImage {
        let c = PixelCanvas(width: 512, height: 512)
        let geo = subject == "geography"
        c.fillStyle(geo ? "#e7e9d8" : "#e9dcc0")
        c.fillRect(0, 0, 512, 512)
        c.strokeStyle(geo ? "rgba(31,111,120,0.22)" : "rgba(122,31,43,0.22)")
        for y in stride(from: -512.0, to: 1024, by: 28) {
            for x in stride(from: -512.0, to: 1024, by: 28) {
                // JavaScript's `%` keeps the sign of the dividend; truncatingRemainder does the same.
                let shift = (y / 28).truncatingRemainder(dividingBy: 2) * 14
                c.circlePath(x + shift, y, 7)
                c.strokeCurrentPath(width: 2)
            }
        }
        c.grain(width: 512, height: 512, seed: 3, dots: 3000, darkAlpha: 0.06, lightAlpha: 0.1)
        return c.image()
    }

    /// The striped side of a page block.
    static func pageEdge() -> CGImage {
        let c = PixelCanvas(width: 64, height: 256)
        c.fillStyle("#efe4c8")
        c.fillRect(0, 0, 64, 256)
        var rng = SeededRandom(seed: 9)
        for y in stride(from: 0, to: 256, by: 2) {
            c.ctx.setFillColor(CGColor(srgbRed: 120 / 255, green: 95 / 255, blue: 50 / 255, alpha: CGFloat(0.10 + rng.next() * 0.22)))
            c.fillRect(0, Double(y), 64, 1)
        }
        return c.image()
    }

    static func make(subject: String) -> CoverTextures {
        subject == "geography" ? geographyCover() : historyCover()
    }
}
