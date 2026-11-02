import CoreGraphics
import CoreText
import Foundation

struct HitRegion: Equatable {
    enum Kind: Equatable {
        case recall(key: String, level: RecallLevel)
        case term(id: String)
    }

    var kind: Kind
    /// In page units (1280 x 1820), before any density scaling.
    var rect: CGRect
}

enum PageFace { case front, back }

struct PageRenderOptions {
    var face: PageFace
    var rtl: Bool
    var subject: String
    var recall: RecallState?
    var revealAll: Bool = false
    /// Bitmap pixels per page unit (1 = 1280 x 1820; reading up close asks for more).
    var density: Double = 1
    var images: [String: CGImage] = [:]
    var measure: Measure = PageFonts.measure
}

/// Draws a physical page into a bitmap: paper, header, blocks, ink blots over hidden answers, folio. Port of `drawPage`.
enum PageRenderer {
    static func pixelSize(density: Double) -> (w: Int, h: Int) {
        (Int((PageGeometry.width * density).rounded()), Int((PageGeometry.height * density).rounded()))
    }

    private static let noiseTile: CGImage = {
        let c = PixelCanvas(width: 256, height: 256)
        var rnd = SeededRandom(seed: 7)
        for _ in 0..<2600 {
            c.fillStyle(rnd.next() > 0.5 ? "rgba(90,60,20,0.05)" : "rgba(255,255,255,0.10)")
            let x = rnd.next() * 256
            let y = rnd.next() * 256
            let w = 1 + rnd.next() * 2
            let h = 1 + rnd.next() * 2
            c.fillRect(x, y, w, h)
        }
        c.strokeStyle("rgba(120,90,40,0.04)")
        c.ctx.setLineWidth(1)
        for _ in 0..<60 {
            let x = rnd.next() * 256
            let y = rnd.next() * 256
            c.line(x, y, x + (rnd.next() - 0.5) * 60, y + (rnd.next() - 0.5) * 8)
            c.ctx.strokePath()
        }
        return c.image()
    }()

    static func draw(_ phys: PhysicalPage?, _ o: PageRenderOptions) -> (image: CGImage, hits: [HitRegion]) {
        let size = pixelSize(density: o.density)
        let c = PixelCanvas(pixelWidth: size.w, pixelHeight: size.h, scale: Double(size.w) / PageGeometry.width)
        let g = c.ctx
        let P = PagePalette.forSubject(o.subject)
        let rtl = o.rtl
        let W = PageGeometry.width, H = PageGeometry.height
        let gutterLeft = (o.face == .front) != rtl
        let left = gutterLeft ? PageGeometry.marginGutter : PageGeometry.marginOuter
        var hits: [HitRegion] = []

        c.fillStyle(P.paper)
        c.fillRect(0, 0, W, H)
        // Paper grain: the 256 px tile repeated over the page.
        var ty = 0.0
        while ty < H {
            var tx = 0.0
            while tx < W {
                g.saveGState()
                g.translateBy(x: CGFloat(tx), y: CGFloat(ty + 256))
                g.scaleBy(x: 1, y: -1)
                g.draw(noiseTile, in: CGRect(x: 0, y: 0, width: 256, height: 256))
                g.restoreGState()
                tx += 256
            }
            ty += 256
        }
        // Foxing: a soft darker rim, stronger at the outer edge and toward the gutter.
        c.fillRectWithGradient(
            CGRect(x: 0, y: 0, width: W, height: H),
            from: CGPoint(x: gutterLeft ? 0 : W, y: 0), to: CGPoint(x: gutterLeft ? W : 0, y: 0),
            stops: [(0, PixelCanvas.css("rgba(70,45,15,0.20)")), (0.12, PixelCanvas.css("rgba(70,45,15,0.04)")), (1, PixelCanvas.css("rgba(70,45,15,0)"))]
        )
        c.fillRectWithGradient(
            CGRect(x: 0, y: 0, width: W, height: H), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: H),
            stops: [
                (0, PixelCanvas.css("rgba(70,45,15,0.10)")), (0.05, PixelCanvas.css("rgba(70,45,15,0)")),
                (0.95, PixelCanvas.css("rgba(70,45,15,0)")), (1, PixelCanvas.css("rgba(70,45,15,0.12)"))
            ]
        )

        guard let phys else { return (c.image(), hits) } // blank sheet

        let state = o.recall
        let dim = (state?.isEnabled ?? false) && !o.revealAll

        func concealed(_ level: RecallLevel, key: String) -> Bool {
            guard !o.revealAll, let state else { return false }
            return state.isConcealed(target: level, key: key, pageID: phys.id)
        }
        func inPlay(_ level: RecallLevel) -> Bool {
            guard let state else { return false }
            return state.isEnabled && state.level.conceals(level)
        }

        func drawRich(_ r: RichLayout, _ ox: Double, _ oy: Double, _ color: PageColor) {
            for ln in r.lines {
                let base = oy + ln.baseline
                for run in r.runs where run.top == ln.top {
                    let absKey = RecallState.key(pageID: phys.id, scope: run.key)
                    let x = ox + run.x, y = oy + run.top + r.lh * 0.12, w = run.w, h = r.lh * 0.78
                    if concealed(run.level, key: absKey) {
                        // Ink blot: the answer is not drawn at all.
                        c.roundRectPath(x - 6, y, w + 12, h, 14)
                        c.fillPathWithGradient(from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + h), stops: [(0, P.blot), (1, PixelCanvas.css("#1b130b"))])
                        c.strokeStyle("rgba(242,184,75,0.55)")
                        c.roundRectPath(x - 6, y, w + 12, h, 14)
                        c.strokeCurrentPath(width: 3)
                        hits.append(HitRegion(kind: .recall(key: absKey, level: run.level), rect: CGRect(x: x - 10, y: y - 6, width: w + 20, height: h + 12)))
                    } else {
                        let marker = o.revealAll && (state?.isEnabled ?? false) ? PixelCanvas.css("rgba(242,184,75,0.55)") : P.marker(level: run.level.rawValue)
                        c.fillStyle(marker)
                        c.roundRectPath(x - 5, y + 4, w + 10, h - 4, 10)
                        c.fillCurrentPath()
                        if inPlay(run.level) {
                            hits.append(HitRegion(kind: .recall(key: absKey, level: run.level), rect: CGRect(x: x - 10, y: y - 6, width: w + 20, height: h + 12)))
                        }
                    }
                }
                for f in ln.frags {
                    // Concealed recall fragments are skipped (the blot is already drawn); everything else is drawn.
                    if f.kind == .recall, let level = f.level, let runKey = f.runKey,
                       concealed(level, key: RecallState.key(pageID: phys.id, scope: runKey)) { continue }
                    var col = color
                    if dim && f.kind != .recall { col = P.inkDim }
                    if f.kind == .term { col = P.accent }
                    c.fillStyle(col)
                    c.strokeStyle(col)
                    // A hair of stroke thickens Amiri's thin hairlines so small text stays legible when the page is far from the eye.
                    c.text(f.text, font: PageFonts.ctFont(f.font), x: ox + f.x, baseline: base, hairline: f.font.bold ? 1.1 : 1.5)
                    if f.kind == .term {
                        c.strokeStyle(P.accent)
                        g.saveGState()
                        g.setLineDash(phase: 0, lengths: [2, 7])
                        g.setLineCap(.round)
                        c.line(ox + f.x, base + 12, ox + f.x + f.w, base + 12)
                        c.strokeCurrentPath(width: 3)
                        g.restoreGState()
                    }
                }
                for t in r.terms where t.top == ln.top {
                    hits.append(HitRegion(kind: .term(id: t.id), rect: CGRect(x: ox + t.x - 8, y: oy + t.top, width: t.w + 16, height: r.lh)))
                }
            }
        }

        func drawPart(_ part: DisplayPart, _ ox: Double, _ oy: Double) {
            switch part {
            case .rich(let r, let x, let y, let color):
                drawRich(r, left + x, oy + y, color)
            case .rect(let x, let y, let w, let h, let fill, let stroke, let radius, let lineWidth):
                if let fill {
                    c.fillStyle(fill)
                    c.roundRectPath(ox + x, oy + y, w, h, radius)
                    c.fillCurrentPath()
                }
                if let stroke {
                    c.strokeStyle(stroke)
                    c.roundRectPath(ox + x, oy + y, w, h, radius)
                    c.strokeCurrentPath(width: lineWidth)
                }
            case .dot(let cx, let cy, let r, let fill):
                c.fillStyle(fill)
                c.circlePath(ox + cx, oy + cy, r)
                c.fillCurrentPath()
            case .num(let cx, let cy, let r, let n, let size, let fill, let color):
                c.fillStyle(fill)
                c.circlePath(ox + cx, oy + cy, r)
                c.fillCurrentPath()
                c.fillStyle(color)
                c.text(String(n), font: PageFonts.ctFont(FontSpec(size: size, bold: true)), x: ox + cx, baseline: oy + cy + size * 0.36, align: .center)
            case .arrow(let cx, let y, let h, let color):
                c.strokeStyle(color)
                c.fillStyle(color)
                g.setLineCap(.round)
                g.setLineJoin(.round)
                c.line(ox + cx, oy + y, ox + cx, oy + y + h - 14)
                c.strokeCurrentPath(width: 6)
                g.move(to: CGPoint(x: ox + cx - 16, y: oy + y + h - 26))
                g.addLine(to: CGPoint(x: ox + cx, y: oy + y + h))
                g.addLine(to: CGPoint(x: ox + cx + 16, y: oy + y + h - 26))
                g.closePath()
                g.fillPath()
            case .label(let text, let x, let y, let w, let size, let color, let bold, let alignRight, let lh):
                c.fillStyle(color)
                c.text(
                    text, font: PageFonts.ctFont(FontSpec(size: size, bold: bold)),
                    x: ox + (alignRight ? x + w : x), baseline: oy + y + (lh ?? size * 1.6) * 0.72, align: alignRight ? .right : .left
                )
            case .image(let name, let alt, let x, let y, let w, let h):
                c.fillStyle(P.card)
                c.roundRectPath(ox + x, oy + y, w, h, 18)
                c.fillCurrentPath()
                c.strokeStyle(P.cardEdge)
                g.saveGState()
                g.setLineDash(phase: 0, lengths: [14, 10])
                c.roundRectPath(ox + x, oy + y, w, h, 18)
                c.strokeCurrentPath(width: 3)
                g.restoreGState()
                if let image = o.images[name] {
                    g.saveGState()
                    c.roundRectPath(ox + x, oy + y, w, h, 18)
                    g.clip()
                    g.translateBy(x: CGFloat(ox + x), y: CGFloat(oy + y + h))
                    g.scaleBy(x: 1, y: -1)
                    g.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                    g.restoreGState()
                } else {
                    c.fillStyle(P.inkDim)
                    c.text(alt, font: PageFonts.ctFont(FontSpec(size: 34, bold: false)), x: ox + x + w / 2, baseline: oy + y + h / 2, align: .center)
                }
            }
        }

        // Header
        let info = HeaderInfo(title: phys.title, dateLabel: phys.dateLabel, part: phys.part, parts: phys.parts)
        let header = PageLayout.header(info, measure: o.measure)
        let contentW = PageGeometry.contentWidth
        let hx = rtl ? left + contentW : left
        let align: TextAlign = rtl ? .right : .left
        var lessonSize = 38.0
        while lessonSize > 26 && o.measure(phys.lessonTitle, FontSpec(size: lessonSize, bold: true)) > contentW { lessonSize -= 2 }
        c.fillStyle(P.accent)
        c.text(phys.lessonTitle, font: PageFonts.ctFont(FontSpec(size: lessonSize, bold: true)), x: hx, baseline: PageGeometry.marginTop + 30, align: align)
        c.fillStyle(P.ink)
        for (i, line) in header.lines.enumerated() {
            c.text(line, font: PageFonts.ctFont(FontSpec(size: header.size, bold: true)), x: hx, baseline: header.titleY + Double(i) * header.size * 1.3, align: align)
        }
        if let dateY = header.dateY, let date = phys.dateLabel {
            c.fillStyle(P.inkDim)
            c.text(date, font: PageFonts.ctFont(FontSpec(size: 36, bold: false)), x: hx, baseline: dateY, align: align)
        }
        let ry = header.ruleY
        let ax = rtl ? left + contentW - 120 : left
        c.fillStyle(P.rule)
        c.fillRect(left, ry + 2, contentW, 2)
        c.fillStyle(P.accent)
        c.fillRect(ax, ry, 120, 5)

        // Blocks
        var by = header.bodyY
        for placed in phys.blocks {
            for part in placed.layout.parts { drawPart(part, left, by) }
            by += placed.layout.height + PageGeometry.gap
        }

        // Folio (page number)
        c.fillStyle(P.inkDim)
        c.text("— \(phys.number) —", font: PageFonts.ctFont(FontSpec(size: 40, bold: false)), x: W / 2, baseline: H - 62, align: .center)
        return (c.image(), hits)
    }
}
