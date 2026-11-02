import CoreGraphics
import CoreText
import Foundation

/// The little random generator the web scene's textures use (Lehmer, 16807 mod 2^31-1), so a given seed draws the same grain.
struct SeededRandom {
    private var state: Int64

    init(seed: Int) {
        state = Int64(seed)
    }

    /// Next value in [0, 1).
    mutating func next() -> Double {
        state = (state * 16807) % 2147483647
        return Double(state) / 2147483647
    }
}

extension PageColor {
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

enum TextAlign { case left, center, right }

/// A bitmap with a 2D-canvas style coordinate system (origin top left, y down), so the page, cover and desk drawing code can
/// follow the web scene operation by operation.
final class PixelCanvas {
    let ctx: CGContext
    let pixelWidth: Int
    let pixelHeight: Int

    /// `scale` maps logical units to pixels (a page is 1280 logical units wide at any density).
    init(pixelWidth: Int, pixelHeight: Int, scale: Double = 1) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            fatalError("could not create a \(pixelWidth)x\(pixelHeight) bitmap")
        }
        ctx = context
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
    }

    convenience init(width: Int, height: Int) {
        self.init(pixelWidth: width, pixelHeight: height, scale: 1)
    }

    func image() -> CGImage {
        guard let image = ctx.makeImage() else { fatalError("could not read back the bitmap") }
        return image
    }

    // MARK: Colours

    func fillStyle(_ c: PageColor) { ctx.setFillColor(c.cgColor) }
    func strokeStyle(_ c: PageColor) { ctx.setStrokeColor(c.cgColor) }
    func fillStyle(_ css: String) { ctx.setFillColor(PixelCanvas.css(css).cgColor) }
    func strokeStyle(_ css: String) { ctx.setStrokeColor(PixelCanvas.css(css).cgColor) }
    func gray(_ v: Double) -> PageColor { PageColor(r: v / 255, g: v / 255, b: v / 255) }

    /// `#rrggbb` or `rgba(r,g,b,a)` strings, as the web scene wrote them.
    static func css(_ text: String) -> PageColor {
        if text.hasPrefix("#"), let value = UInt32(text.dropFirst(), radix: 16) { return PageColor(rgb: value) }
        if text.hasPrefix("rgb") {
            let inner = text.drop { $0 != "(" }.dropFirst().dropLast()
            let parts = inner.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if parts.count >= 3 {
                return PageColor(red: parts[0], green: parts[1], blue: parts[2], alpha: parts.count > 3 ? parts[3] : 1)
            }
        }
        return PageColor(r: 0, g: 0, b: 0)
    }

    // MARK: Shapes

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// `roundRect` with the corner radius limited to half the shorter side, like the web scene's helper.
    func roundRectPath(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
        let rr = max(0, min(r, w / 2, h / 2))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: rr, cornerHeight: rr, transform: nil))
    }

    func circlePath(_ cx: Double, _ cy: Double, _ r: Double) {
        ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        ctx.move(to: CGPoint(x: x0, y: y0))
        ctx.addLine(to: CGPoint(x: x1, y: y1))
    }

    func fillCurrentPath() { ctx.fillPath() }
    func strokeCurrentPath(width: Double) {
        ctx.setLineWidth(CGFloat(width))
        ctx.strokePath()
    }

    // MARK: Gradients

    /// Fills the current path (already added to the context) with a linear gradient; colours beyond the ends extend, like canvas.
    func fillPathWithGradient(from a: CGPoint, to b: CGPoint, stops: [(Double, PageColor)]) {
        guard let gradient = PixelCanvas.gradient(stops) else { return }
        ctx.saveGState()
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    func fillRectWithGradient(_ rect: CGRect, from a: CGPoint, to b: CGPoint, stops: [(Double, PageColor)]) {
        ctx.addRect(rect)
        fillPathWithGradient(from: a, to: b, stops: stops)
    }

    static func gradient(_ stops: [(Double, PageColor)]) -> CGGradient? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGGradient(
            colorsSpace: space,
            colors: stops.map { $0.1.cgColor } as CFArray,
            locations: stops.map { CGFloat($0.0) }
        )
    }

    // MARK: Text

    /// Draws `text` on a baseline. Right-aligned text ends at `x`; the page text uses the same widths it was laid out with.
    /// `hairline` adds a stroke of that width in the stroke colour (the web scene thickened Amiri's thin strokes this way).
    func text(_ text: String, font: CTFont, x: Double, baseline: Double, align: TextAlign = .left, hairline: Double? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let left: Double
        switch align {
        case .left: left = x
        case .center: left = x - width / 2
        case .right: left = x - width
        }
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: left, y: baseline)
        if let hairline {
            ctx.setLineWidth(CGFloat(hairline))
            ctx.setLineJoin(.round)
            ctx.setTextDrawingMode(.fillStroke)
        } else {
            ctx.setTextDrawingMode(.fill)
        }
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Grain

    /// Speckle of dark and light dots (`grain` in cover.js).
    func grain(width: Double, height: Double, seed: Int, dots: Int, darkAlpha: Double, lightAlpha: Double) {
        var rng = SeededRandom(seed: seed)
        for _ in 0..<dots {
            let dark = rng.next() > 0.5
            ctx.setFillColor(CGColor(srgbRed: dark ? 0 : 1, green: dark ? 0 : 1, blue: dark ? 0 : 1, alpha: dark ? darkAlpha : lightAlpha))
            let s = 1 + rng.next() * 3
            let x = rng.next() * width
            let y = rng.next() * height
            fillRect(x, y, s, s)
        }
    }
}
