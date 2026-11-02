import Foundation

/// What a block draws, in coordinates local to the content column (origin at the block's top start corner).
enum DisplayPart: Equatable {
    case rich(RichLayout, x: Double, y: Double, color: PageColor)
    case rect(x: Double, y: Double, w: Double, h: Double, fill: PageColor?, stroke: PageColor?, radius: Double, lineWidth: Double)
    case dot(cx: Double, cy: Double, r: Double, fill: PageColor)
    case num(cx: Double, cy: Double, r: Double, n: Int, size: Double, fill: PageColor, color: PageColor)
    case arrow(cx: Double, y: Double, h: Double, color: PageColor)
    case label(text: String, x: Double, y: Double, w: Double, size: Double, color: PageColor, bold: Bool, alignRight: Bool, lh: Double?)
    case image(name: String, alt: String, x: Double, y: Double, w: Double, h: Double)
}

struct BlockLayout: Equatable {
    var height: Double
    var parts: [DisplayPart]
    var index: Int
}

struct LayoutEnv {
    var measure: Measure
    var rtl: Bool
    var scale: Double
    var palette: PagePalette
    var width: Double
}

enum BlockLayouter {
    private static func filled(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Port of `layoutBlock` in pagetex.js, case by case.
    static func layout(_ block: Block, index: Int, env: LayoutEnv) -> BlockLayout {
        let rtl = env.rtl
        let s = env.scale
        let P = env.palette
        let W = env.width
        var parts: [DisplayPart] = []
        var y = 0.0

        func rich(_ source: String, _ name: String, size: Double, bold: Bool = false, width: Double? = nil, lineHeight: Double = 1.85) -> RichLayout {
            RichLayouter.layout(
                source, measure: env.measure, width: width ?? W, rtl: rtl,
                style: RichStyle(size: size, bold: bold, lineHeight: lineHeight), slot: "\(index).\(name)"
            )
        }
        func text(_ r: RichLayout, _ x: Double, _ yy: Double, _ color: PageColor) {
            parts.append(.rich(r, x: x, y: yy, color: color))
        }
        func rect(_ x: Double, _ yy: Double, _ w: Double, _ h: Double, fill: PageColor? = nil, stroke: PageColor? = nil, r: Double = 0, lw: Double = 2) {
            parts.append(.rect(x: x, y: yy, w: w, h: h, fill: fill, stroke: stroke, radius: r, lineWidth: lw))
        }
        /// A box of width `w` placed at inset `x` from the start edge.
        func startX(_ x: Double, _ w: Double) -> Double { rtl ? W - x - w : x }
        func title(_ value: String?, gap: Double) {
            guard let value = filled(value) else { return }
            let t = rich(value, "t", size: 40 * s, bold: true)
            text(t, 0, y, P.accent)
            y += t.height + gap
        }

        switch block {
        case .heading(let value, let level):
            let size = (level <= 1 ? 76.0 : level == 2 ? 60.0 : 50.0) * s
            let r = rich(value, "h", size: size, bold: true, lineHeight: 1.45)
            text(r, 0, 0, P.ink)
            y = r.height
            if level <= 2 {
                rect(startX(0, 90 * s), y + 6, 90 * s, 5, fill: P.accent, r: 2)
                y += 26
            }

        case .paragraph(let value):
            let r = rich(value, "p", size: 52 * s)
            text(r, 0, 0, P.ink)
            y = r.height

        case .list(let listTitle, let items, let ordered):
            title(listTitle, gap: 8 * s)
            let mark = 64 * s
            for (i, item) in items.enumerated() {
                let r = rich(item, "i\(i)", size: 50 * s, width: W - mark)
                parts.append(.label(
                    text: ordered ? String(i + 1) : "•", x: startX(0, mark), y: y, w: mark, size: 44 * s,
                    color: P.accent, bold: true, alignRight: rtl, lh: r.lh
                ))
                text(r, rtl ? 0 : mark, y, P.ink)
                y += r.height + 12 * s
            }
            y -= 12 * s

        case .keyPoint(let label, let value):
            let pad = 30 * s
            let bar = 10 * s
            let inner = W - pad * 2 - bar
            var yy = pad
            let r1 = filled(label).map { rich($0, "l", size: 34 * s, bold: true, width: inner, lineHeight: 1.5) }
            let r2 = rich(value, "k", size: 54 * s, bold: true, width: inner, lineHeight: 1.7)
            let h = pad * 2 + (r1.map { $0.height + 6 * s } ?? 0) + r2.height
            rect(0, 0, W, h, fill: P.card, stroke: P.cardEdge, r: 22)
            rect(startX(0, bar), 0, bar, h, fill: P.accent, r: 4)
            let tx = rtl ? pad : pad + bar
            if let r1 {
                text(r1, tx, yy, P.accent)
                yy += r1.height + 6 * s
            }
            text(r2, tx, yy, P.ink)
            y = h

        case .quote(let value, let source):
            let bar = 8 * s
            let pad = 34 * s
            let inner = W - bar - pad
            let r = rich(value, "q", size: 54 * s, width: inner)
            var h = r.height
            var src: RichLayout?
            if let source = filled(source) {
                let layout = rich(source, "s", size: 38 * s, width: inner)
                src = layout
                h += layout.height + 10 * s
            }
            rect(startX(0, bar), 0, bar, h, fill: P.rule, r: 4)
            let tx = rtl ? 0 : bar + pad
            text(r, tx, 0, P.ink)
            if let src { text(src, tx, r.height + 10 * s, P.inkDim) }
            y = h

        case .timeline(let blockTitle, let events):
            title(blockTitle, gap: 12 * s)
            let gutter = 70 * s
            let inner = W - gutter
            for (i, ev) in events.enumerated() {
                let d = rich(ev.date, "e\(i)d", size: 42 * s, bold: true, width: inner, lineHeight: 1.5)
                let t = rich(ev.title, "e\(i)t", size: 50 * s, bold: true, width: inner, lineHeight: 1.6)
                let x = filled(ev.detail).map { rich($0, "e\(i)x", size: 44 * s, width: inner, lineHeight: 1.7) }
                let h = d.height + t.height + (x?.height ?? 0) + 26 * s
                let tx = rtl ? 0 : gutter
                parts.append(.dot(cx: rtl ? W - 18 * s : 18 * s, cy: 22 * s + y, r: 11 * s, fill: P.accent))
                if i < events.count - 1 {
                    rect(rtl ? W - 18 * s - 2 : 18 * s - 2, y + 38 * s, 4, h - 22 * s, fill: P.rule, r: 2)
                }
                text(d, tx, y, P.accent)
                text(t, tx, y + d.height, P.ink)
                if let x { text(x, tx, y + d.height + t.height, P.inkDim) }
                y += h
            }
            y -= 20 * s

        case .stats(let blockTitle, let items):
            title(blockTitle, gap: 12 * s)
            let gap = 26 * s
            let cw = (W - gap) / 2
            var rowH = 0.0
            for (i, it) in items.enumerated() {
                let col = Double(i % 2)
                let px = rtl ? W - cw - col * (cw + gap) : col * (cw + gap)
                let pad = 22 * s
                let inner = cw - pad * 2
                let v = rich(it.value, "v\(i)", size: 78 * s, bold: true, width: inner, lineHeight: 1.3)
                let l = rich(it.label, "l\(i)", size: 40 * s, width: inner, lineHeight: 1.6)
                let n = filled(it.note).map { rich($0, "n\(i)", size: 34 * s, width: inner, lineHeight: 1.6) }
                let h = pad * 2 + v.height + l.height + (n?.height ?? 0)
                rect(px, y, cw, h, fill: P.card, stroke: P.cardEdge, r: 20)
                text(v, px + pad, y + pad, P.accent)
                text(l, px + pad, y + pad + v.height, P.ink)
                if let n { text(n, px + pad, y + pad + v.height + l.height, P.inkDim) }
                rowH = max(rowH, h)
                if i % 2 == 1 || i == items.count - 1 {
                    y += rowH + gap
                    rowH = 0
                }
            }
            y -= gap

        case .comparison(let blockTitle, _, let columns, let rows):
            title(blockTitle, gap: 12 * s)
            if columns.count < 2 {
                for (r, row) in rows.enumerated() {
                    let pad = 26 * s
                    let inner = W - pad * 2
                    let lab = rich(row.label, "r\(r)l", size: 48 * s, bold: true, width: inner, lineHeight: 1.55)
                    let cell = (row.cells.first ?? "").components(separatedBy: "\n")
                    let cells = cell.enumerated().map { k, c in
                        rich(c, "r\(r)c0n\(k)", size: 46 * s, width: inner - (cell.count > 1 ? 40 * s : 0), lineHeight: 1.75)
                    }
                    let h = pad * 2 + lab.height + cells.reduce(0) { $0 + $1.height + 6 * s }
                    rect(0, y, W, h, fill: P.card, stroke: P.cardEdge, r: 22)
                    text(lab, pad, y + pad, P.accent)
                    var yy = y + pad + lab.height + 6 * s
                    for c in cells {
                        if cell.count > 1 {
                            parts.append(.label(
                                text: "•", x: rtl ? W - pad - 30 * s : pad, y: yy, w: 30 * s, size: 40 * s,
                                color: P.accent, bold: true, alignRight: rtl, lh: c.lh
                            ))
                        }
                        text(c, pad + (cell.count > 1 && !rtl ? 40 * s : 0), yy, P.ink)
                        yy += c.height + 6 * s
                    }
                    y += h + 22 * s
                }
                y -= 22 * s
            } else {
                let n = Double(columns.count)
                let labelW = W * 0.24
                let cw = (W - labelW) / n
                let hdr = columns.enumerated().map { i, c in
                    rich(c, "c\(i)", size: 38 * s, bold: true, width: cw - 20 * s, lineHeight: 1.5)
                }
                let hh = (hdr.map(\.height).max() ?? 0) + 20 * s
                func colX(_ i: Int) -> Double { rtl ? W - labelW - Double(i + 1) * cw : labelW + Double(i) * cw }
                for (i, h) in hdr.enumerated() { text(h, colX(i) + 10 * s, y + 10 * s, P.accent) }
                rect(0, y + hh, W, 3, fill: P.rule)
                y += hh + 8 * s
                for (r, row) in rows.enumerated() {
                    let lab = rich(row.label, "r\(r)l", size: 42 * s, bold: true, width: labelW - 20 * s, lineHeight: 1.5)
                    let cells = row.cells.enumerated().map { i, c in
                        rich(c, "r\(r)c\(i)", size: 40 * s, width: cw - 20 * s, lineHeight: 1.65)
                    }
                    let h = max(lab.height, cells.map(\.height).max() ?? 0) + 24 * s
                    text(lab, rtl ? W - labelW + 10 * s : 10 * s, y + 12 * s, P.ink)
                    for (i, c) in cells.enumerated() { text(c, colX(i) + 10 * s, y + 12 * s, P.ink) }
                    rect(0, y + h, W, 2, fill: P.rule)
                    y += h + 4 * s
                }
            }

        case .causeEffect(let blockTitle, let stages):
            title(blockTitle, gap: 14 * s)
            for (si, st) in stages.enumerated() {
                let last = si == stages.count - 1
                if let label = filled(st.label) {
                    let l = rich(label, "s\(si)l", size: 34 * s, bold: true, lineHeight: 1.5)
                    text(l, 0, y, P.accent)
                    y += l.height + 4 * s
                }
                for (ni, node) in st.nodes.enumerated() {
                    let pad = 24 * s
                    let r = rich(node, "s\(si)n\(ni)", size: 46 * s, bold: last, width: W - pad * 2, lineHeight: 1.7)
                    let h = r.height + pad * 2
                    // The last stage keeps the history-red wash in every subject, as in the web scene.
                    rect(
                        0, y, W, h,
                        fill: last ? PageColor(red: 122, green: 31, blue: 43, alpha: 0.14) : P.card,
                        stroke: last ? P.accent : P.cardEdge, r: 20, lw: last ? 3 : 2
                    )
                    text(r, pad, y + pad, P.ink)
                    y += h + 14 * s
                }
                if !last {
                    parts.append(.arrow(cx: W / 2, y: y, h: 44 * s, color: P.accent))
                    y += 58 * s
                }
            }
            y -= 14 * s

        case .process(let blockTitle, let steps):
            title(blockTitle, gap: 12 * s)
            let gutter = 80 * s
            let inner = W - gutter
            for (i, st) in steps.enumerated() {
                let a = rich(st.title, "s\(i)t", size: 50 * s, bold: true, width: inner, lineHeight: 1.6)
                let b = filled(st.detail).map { rich($0, "s\(i)d", size: 44 * s, width: inner, lineHeight: 1.7) }
                let h = a.height + (b?.height ?? 0) + 22 * s
                parts.append(.num(cx: rtl ? W - 26 * s : 26 * s, cy: y + 30 * s, r: 24 * s, n: i + 1, size: 30 * s, fill: P.accent, color: P.paper))
                if i < steps.count - 1 {
                    rect(rtl ? W - 26 * s - 2 : 26 * s - 2, y + 56 * s, 4, h - 30 * s, fill: P.rule, r: 2)
                }
                text(a, rtl ? 0 : gutter, y, P.ink)
                if let b { text(b, rtl ? 0 : gutter, y + a.height, P.inkDim) }
                y += h
            }
            y -= 22 * s

        case .definitions(let blockTitle, let items):
            title(blockTitle, gap: 12 * s)
            for (i, d) in items.enumerated() {
                let pad = 26 * s
                let inner = W - pad * 2
                let a = rich(d.term, "d\(i)t", size: 52 * s, bold: true, width: inner, lineHeight: 1.6)
                let b = rich(d.definition, "d\(i)x", size: 46 * s, width: inner, lineHeight: 1.75)
                let h = pad * 2 + a.height + b.height
                rect(0, y, W, h, fill: P.card, stroke: P.cardEdge, r: 22)
                text(a, pad, y + pad, P.accent)
                text(b, pad, y + pad + a.height, P.ink)
                y += h + 20 * s
            }
            y -= 20 * s

        case .image(let panel):
            let h = 420 * s
            parts.append(.image(name: panel.name, alt: panel.alt, x: 0, y: 0, w: W, h: h))
            y = h
            if let caption = filled(panel.caption) {
                let c = rich(caption, "cap", size: 36 * s, lineHeight: 1.6)
                text(c, 0, y + 12 * s, P.inkDim)
                y += c.height + 12 * s
            }

        case .unsupported:
            let r = rich("…", "u", size: 40 * s)
            text(r, 0, 0, P.inkDim)
            y = r.height
        }
        return BlockLayout(height: max(0, y), parts: parts, index: index)
    }
}
