import Foundation

/// A font as the page layout sees it: a rounded size and bold or regular (`fontOf` in pagetex.js rounds the size).
struct FontSpec: Hashable {
    var size: Double
    var bold: Bool

    init(size: Double, bold: Bool) {
        self.size = size.rounded()
        self.bold = bold
    }
}

/// Width of a string in a font. The real one measures with Core Text; tests pass a fixed-width stand-in.
typealias Measure = (String, FontSpec) -> Double

struct RichFragment: Equatable {
    enum Kind: Equatable { case text, bold, term, recall }

    var text: String
    var kind: Kind
    var termID: String?
    var level: RecallLevel?
    var index: Int?
    /// The whole recall target this fragment belongs to (the fragment itself may be one word of it).
    var target: String?
    var font = FontSpec(size: 0, bold: false)
    var w = 0.0
    var x = 0.0
    /// `"<slot>.<recall index>"`, set on placed recall fragments.
    var runKey: String?
}

struct RichWord: Equatable {
    var frags: [RichFragment]
    var w = 0.0
}

struct RichLine: Equatable {
    var top: Double
    var frags: [RichFragment]
    var baseline: Double
}

/// One hidden-able answer on a line: neighbouring fragments of the same recall target merged, gaps included.
struct RecallRun: Equatable {
    var key: String
    var level: RecallLevel
    var x: Double
    var w: Double
    var top: Double
    var h: Double
    var text: String
}

struct TermHit: Equatable {
    var id: String
    var x: Double
    var w: Double
    var top: Double
    var h: Double
}

struct RichLayout: Equatable {
    var height: Double
    var lines: [RichLine]
    var runs: [RecallRun]
    var terms: [TermHit]
    var size: Double
    var lh: Double
}

struct RichStyle {
    var size: Double
    var bold = false
    var lineHeight = 1.85
}

/// Whitespace as JavaScript's `\s` sees it, so line breaking matches the web scene on the same text.
func isJSWhitespace(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
    default: return false
    }
}

/// `string.split(/\s+/)` of JavaScript, including the empty first or last piece when the text starts or ends with space.
func splitOnWhitespace(_ text: String) -> [String] {
    var pieces: [String] = []
    var current = String.UnicodeScalarView()
    var inSpace = false
    for scalar in text.unicodeScalars {
        if isJSWhitespace(scalar) {
            if !inSpace {
                pieces.append(String(current))
                current = String.UnicodeScalarView()
                inSpace = true
            }
        } else {
            inSpace = false
            current.append(scalar)
        }
    }
    pieces.append(String(current))
    return pieces
}

enum RichLayouter {
    /// Splits inline markup into words made of styled fragments; one word can hold several fragments (`[[1815|e]]،`).
    static func toWords(_ source: String) -> [RichWord] {
        var words: [RichWord] = []
        var open = false
        func push(_ frag: RichFragment) {
            if !open {
                words.append(RichWord(frags: []))
                open = true
            }
            words[words.count - 1].frags.append(frag)
        }
        for segment in InlineMarkup.parse(source) {
            let text: String
            var kind = RichFragment.Kind.text
            var termID: String?
            var level: RecallLevel?
            var index: Int?
            switch segment {
            case .text(let t): text = t
            case .bold(let t): text = t; kind = .bold
            case .term(let t, let id): text = t; kind = .term; termID = id
            case .recall(let t, let l, let i): text = t; kind = .recall; level = l; index = i
            }
            // Walk the text as alternating runs of whitespace and non-whitespace.
            var run = String.UnicodeScalarView()
            var runIsSpace = false
            func flush() {
                guard !run.isEmpty else { return }
                if runIsSpace {
                    open = false
                } else {
                    var frag = RichFragment(text: String(run), kind: kind)
                    frag.termID = termID
                    frag.level = level
                    frag.index = index
                    if kind == .recall { frag.target = text }
                    push(frag)
                }
                run = String.UnicodeScalarView()
            }
            for scalar in text.unicodeScalars {
                let isSpace = isJSWhitespace(scalar)
                if !run.isEmpty && isSpace != runIsSpace { flush() }
                runIsSpace = isSpace
                run.append(scalar)
            }
            flush()
        }
        return words
    }

    /// Wraps `source` into lines. Coordinates are local to the content column: x in [0, width] (mirrored when `rtl`).
    static func layout(_ source: String, measure: Measure, width: Double, rtl: Bool, style: RichStyle, slot: String) -> RichLayout {
        var words = toWords(source)
        let size = style.size
        let measuredSpace = measure(" ", FontSpec(size: size, bold: false))
        let spaceW = measuredSpace != 0 ? measuredSpace : size * 0.25
        let lh = size * style.lineHeight

        var lines: [[RichWord]] = []
        var used = 0.0
        for i in words.indices {
            var w = 0.0
            for j in words[i].frags.indices {
                let kind = words[i].frags[j].kind
                let font = FontSpec(size: size, bold: kind == .bold ? true : style.bold)
                words[i].frags[j].font = font
                words[i].frags[j].w = measure(words[i].frags[j].text, font)
                w += words[i].frags[j].w
            }
            words[i].w = w
            if lines.isEmpty { lines.append([]); used = 0 }
            let hasWords = !lines[lines.count - 1].isEmpty
            let need = hasWords ? used + spaceW + w : w
            if need > width && hasWords {
                lines.append([])
                used = 0
            }
            let nowHasWords = !lines[lines.count - 1].isEmpty
            used = nowHasWords ? used + spaceW + w : w
            lines[lines.count - 1].append(words[i])
        }
        if lines.isEmpty { lines.append([]) }

        var runs: [RecallRun] = []
        var terms: [TermHit] = []
        var out: [RichLine] = []
        for (li, line) in lines.enumerated() {
            let top = Double(li) * lh
            var placed: [RichFragment] = []
            var cursor = rtl ? width : 0
            for (wi, word) in line.enumerated() {
                if wi > 0 { cursor += rtl ? -spaceW : spaceW }
                let wx = rtl ? cursor - word.w : cursor
                var fx = rtl ? wx + word.w : wx
                for var frag in word.frags {
                    frag.x = rtl ? fx - frag.w : fx
                    fx += rtl ? -frag.w : frag.w
                    placed.append(frag)
                }
                cursor += rtl ? -word.w : word.w
            }
            // Merge neighbouring fragments of one recall target (and the gap between its words) into runs.
            var open: RecallRun?
            for i in placed.indices {
                if placed[i].kind == .recall, let level = placed[i].level, let index = placed[i].index {
                    let key = "\(slot).\(index)"
                    placed[i].runKey = key
                    if var current = open, current.key == key {
                        let x0 = min(current.x, placed[i].x)
                        let x1 = max(current.x + current.w, placed[i].x + placed[i].w)
                        current.x = x0
                        current.w = x1 - x0
                        open = current
                    } else {
                        if let current = open { runs.append(current) }
                        open = RecallRun(key: key, level: level, x: placed[i].x, w: placed[i].w, top: top, h: lh, text: placed[i].target ?? "")
                    }
                } else if let current = open {
                    runs.append(current)
                    open = nil
                }
                if placed[i].kind == .term, let id = placed[i].termID {
                    terms.append(TermHit(id: id, x: placed[i].x, w: placed[i].w, top: top, h: lh))
                }
            }
            if let current = open { runs.append(current) }
            out.append(RichLine(top: top, frags: placed, baseline: top + size * 1.18 + (lh - size * 1.6) * 0.5))
        }
        return RichLayout(height: Double(lines.count) * lh, lines: out, runs: runs, terms: terms, size: size, lh: lh)
    }
}
