import Foundation

/// A colour in sRGB, kept free of UIKit so page layout can be tested without a display.
struct PageColor: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `0xRRGGBB`.
    init(rgb: UInt32, alpha: Double = 1) {
        self.init(
            r: Double((rgb >> 16) & 0xFF) / 255,
            g: Double((rgb >> 8) & 0xFF) / 255,
            b: Double(rgb & 0xFF) / 255,
            a: alpha
        )
    }

    /// 0-255 channels with an alpha (the `rgba(...)` strings of the web scene).
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(r: red / 255, g: green / 255, b: blue / 255, a: alpha)
    }
}

/// The colours of one subject's pages (`PALETTES` in pagetex.js).
struct PagePalette: Equatable {
    var paper: PageColor
    var paperShade: PageColor
    var ink: PageColor
    var inkDim: PageColor
    var accent: PageColor
    var rule: PageColor
    var card: PageColor
    var cardEdge: PageColor
    var blot: PageColor
    /// Highlighter colours by recall level; index 0 is unused (clear).
    var mark: [PageColor]

    private static let highlighter: [PageColor] = [
        PageColor(red: 0, green: 0, blue: 0, alpha: 0),
        PageColor(red: 242, green: 184, blue: 75, alpha: 0.62),
        PageColor(red: 242, green: 184, blue: 75, alpha: 0.40),
        PageColor(red: 242, green: 184, blue: 75, alpha: 0.22)
    ]

    func marker(level: Int) -> PageColor {
        mark.indices.contains(level) ? mark[level] : mark[0]
    }

    static let history = PagePalette(
        paper: PageColor(rgb: 0xf3e8cd), paperShade: PageColor(rgb: 0xe6d5ae),
        ink: PageColor(rgb: 0x2b1d12), inkDim: PageColor(rgb: 0x5b4b38), accent: PageColor(rgb: 0x7a1f2b),
        rule: PageColor(rgb: 0xb79f73),
        card: PageColor(red: 122, green: 31, blue: 43, alpha: 0.07),
        cardEdge: PageColor(red: 122, green: 31, blue: 43, alpha: 0.35),
        blot: PageColor(rgb: 0x34261a), mark: highlighter
    )

    static let geography = PagePalette(
        paper: PageColor(rgb: 0xeef0e4), paperShade: PageColor(rgb: 0xd9e0d0),
        ink: PageColor(rgb: 0x16272a), inkDim: PageColor(rgb: 0x41575a), accent: PageColor(rgb: 0x1f6f78),
        rule: PageColor(rgb: 0xa9bdb4),
        card: PageColor(red: 31, green: 111, blue: 120, alpha: 0.08),
        cardEdge: PageColor(red: 31, green: 111, blue: 120, alpha: 0.38),
        blot: PageColor(rgb: 0x1e3a3f), mark: highlighter
    )

    /// Unknown subjects use the history palette, like the web scene.
    static func forSubject(_ subject: String) -> PagePalette {
        subject == "geography" ? .geography : .history
    }
}
