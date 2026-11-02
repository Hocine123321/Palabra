import Foundation

/// Page geometry in page-bitmap pixels (`PAGE_W`, `MARGIN`, ... of pagetex.js).
enum PageGeometry {
    static let width = 1280.0
    static let height = 1820.0
    static let marginTop = 110.0
    static let marginBottom = 130.0
    static let marginOuter = 104.0
    static let marginGutter = 152.0
    static let contentWidth = width - marginOuter - marginGutter
    /// Space between two blocks.
    static let gap = 40.0
}

struct HeaderInfo: Equatable {
    var title: String
    var dateLabel: String?
    var part: Int
    var parts: Int
}

struct HeaderLayout: Equatable {
    var size: Double
    var lines: [String]
    var titleY: Double
    var dateY: Double?
    var ruleY: Double
    var bodyY: Double
}

struct PlacedBlock: Equatable {
    var layout: BlockLayout
    var index: Int
}

/// One physical sheet side: a lesson page, or one part of a lesson page that did not fit on one sheet.
struct PhysicalPage: Equatable {
    var id: String
    var baseID: String
    var part: Int
    var parts: Int
    var blocks: [PlacedBlock]
    var scale: Double
    var title: String
    var dateLabel: String?
    var lessonTitle: String
    var glossary: [String: TermDefinition]
    /// Position in the book's list of physical pages, 1-based; set by whoever builds that list.
    var number = 0
}

enum PageLayout {
    /// Title lines, date position and where the header rule sits (shared by pagination and drawing).
    static func header(_ info: HeaderInfo, measure: Measure) -> HeaderLayout {
        let first = info.part == 1
        let size = first ? 70.0 : 54.0
        let title = info.title + (info.parts > 1 ? " · \(info.part)/\(info.parts)" : "")
        let font = FontSpec(size: size, bold: true)
        var lines: [String] = []
        var current = ""
        for word in splitOnWhitespace(title) {
            let candidate = current.isEmpty ? word : current + " " + word
            if measure(candidate, font) > PageGeometry.contentWidth && !current.isEmpty {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        let titleY = PageGeometry.marginTop + (first ? 110 : 88)
        let lastBaseline = titleY + Double(lines.count - 1) * size * 1.3
        let dateY: Double? = first && !(info.dateLabel ?? "").isEmpty ? lastBaseline + 52 : nil
        let ruleY = (dateY ?? lastBaseline) + 34
        return HeaderLayout(size: size, lines: lines, titleY: titleY, dateY: dateY, ruleY: ruleY, bodyY: ruleY + 60)
    }

    static func capacity(_ info: HeaderInfo, measure: Measure) -> Double {
        PageGeometry.height - PageGeometry.marginBottom - header(info, measure: measure).bodyY
    }

    /// Lays a lesson page out on one or more physical pages: shrink the text a little to avoid a nearly empty second page,
    /// otherwise start a new page whenever the next block does not fit.
    static func paginate(_ bookPage: BookPage, measure: @escaping Measure, rtl: Bool, subject: String, scale: Double) -> [PhysicalPage] {
        let palette = PagePalette.forSubject(subject)
        let blocks = bookPage.page.blocks
        func layouts(at scale: Double) -> [BlockLayout] {
            let env = LayoutEnv(measure: measure, rtl: rtl, scale: scale, palette: palette, width: PageGeometry.contentWidth)
            return blocks.enumerated().map { BlockLayouter.layout($1, index: $0, env: env) }
        }
        func total(_ ls: [BlockLayout]) -> Double {
            ls.reduce(0) { $0 + $1.height } + Double(max(0, ls.count - 1)) * PageGeometry.gap
        }
        func info(_ part: Int, _ parts: Int) -> HeaderInfo {
            HeaderInfo(title: bookPage.page.title, dateLabel: bookPage.page.dateLabel, part: part, parts: parts)
        }

        var scale = scale
        var current = layouts(at: scale)
        let cap1 = capacity(info(1, 1), measure: measure)
        if total(current) > cap1 {
            for f in [0.94, 0.88] {
                let trial = layouts(at: scale * f)
                if total(trial) <= cap1 {
                    current = trial
                    scale *= f
                    break
                }
            }
        }

        var pages: [[PlacedBlock]] = []
        var page: [PlacedBlock] = []
        var used = 0.0
        for (index, layout) in current.enumerated() {
            let add = (page.isEmpty ? 0 : PageGeometry.gap) + layout.height
            let room = capacity(info(pages.isEmpty ? 1 : 2, 2), measure: measure)
            if !page.isEmpty && used + add > room {
                pages.append(page)
                page = []
                used = 0
            }
            page.append(PlacedBlock(layout: layout, index: index))
            used += (page.count > 1 ? PageGeometry.gap : 0) + layout.height
        }
        if !page.isEmpty || pages.isEmpty { pages.append(page) }

        return pages.enumerated().map { i, blks in
            PhysicalPage(
                id: pages.count == 1 ? bookPage.id : "\(bookPage.id)~\(i + 1)",
                baseID: bookPage.id, part: i + 1, parts: pages.count, blocks: blks, scale: scale,
                title: bookPage.page.title, dateLabel: bookPage.page.dateLabel,
                lessonTitle: bookPage.lessonTitle, glossary: bookPage.glossary
            )
        }
    }
}
