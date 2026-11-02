import CoreText
import Foundation

/// The page typeface: Amiri (bundled, so Arabic looks the same on every device), then the system Arabic and serif faces for
/// any glyph Amiri lacks. Measuring uses the same fonts the page is drawn with, so lines break where they are drawn.
enum PageFonts {
    private static let lock = NSLock()
    private static var fonts: [FontSpec: CTFont] = [:]
    private static var widths: [Key: Double] = [:]

    private struct Key: Hashable {
        var spec: FontSpec
        var text: String
    }

    private static let registration: Bool = {
        var urls: [URL] = []
        for name in ["Amiri-Regular", "Amiri-Bold"] {
            let bundle = Bundle(for: BundleToken.self)
            if let url = bundle.url(forResource: name, withExtension: "ttf") ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return false }
        // An "already registered" error (a second call, or a test host) is fine: the font is usable either way.
        CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
        return true
    }()

    /// Makes the bundled fonts available to Core Text. Safe to call any number of times.
    @discardableResult
    static func register() -> Bool { registration }

    /// The font for a page text style: Amiri with a fallback cascade.
    static func ctFont(_ spec: FontSpec) -> CTFont {
        _ = register()
        lock.lock()
        defer { lock.unlock() }
        if let cached = fonts[spec] { return cached }
        let name = spec.bold ? "Amiri-Bold" : "Amiri-Regular"
        let base = CTFontCreateWithName(name as CFString, CGFloat(spec.size), nil)
        let fallbacks = ["GeezaPro", "Georgia"].map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, CGFloat(spec.size)) }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontCascadeListAttribute as String: fallbacks] as CFDictionary
        )
        let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(spec.size), nil)
        fonts[spec] = font
        return font
    }

    /// Width of `text` in `spec`, in points of the page bitmap (cached).
    static let measure: Measure = { text, spec in
        let key = Key(spec: spec, text: text)
        PageFonts.lock.lock()
        let cached = PageFonts.widths[key]
        PageFonts.lock.unlock()
        if let cached { return cached }
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): PageFonts.ctFont(spec)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        PageFonts.lock.lock()
        PageFonts.widths[key] = width
        PageFonts.lock.unlock()
        return width
    }
}
