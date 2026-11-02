import CoreGraphics
import XCTest
@testable import Palabra

final class ArtTests: XCTestCase {
    private let fixed: Measure = { text, _ in Double(text.utf16.count) * 14 }

    /// RGBA bytes of an image, row by row from the top.
    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    private func pixel(_ data: [UInt8], _ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    private func page(_ blocks: [Block]) -> BookPage {
        BookPage(
            id: "l/p", number: 1, chapterID: "c", lessonID: "l", lessonTitle: "Lesson",
            page: LessonPage(id: "p", title: "Title", dateLabel: nil, blocks: blocks), glossary: [:]
        )
    }

    private func physical(_ blocks: [Block]) throws -> PhysicalPage {
        var parts = PageLayout.paginate(page(blocks), measure: fixed, rtl: false, subject: "history", scale: 1)
        parts[0].number = 7
        return try XCTUnwrap(parts.first)
    }

    private func options(recall: RecallState? = nil, revealAll: Bool = false, density: Double = 1) -> PageRenderOptions {
        PageRenderOptions(face: .front, rtl: false, subject: "history", recall: recall, revealAll: revealAll, density: density, measure: fixed)
    }

    // MARK: Random

    func testSeededRandomMatchesJS() {
        let golden: [Int: [Double]] = [
            42: [0.00032870750889587566, 0.5245871020129822, 0.7354235321913956, 0.26330554078487006, 0.37622397131110724],
            5: [0.000039131846297128054, 0.6576889407158312, 0.7780266109751661, 0.29325065961724645, 0.6638361870608461],
            11: [0.00008609006185368172, 0.44691566957482864, 0.3116585441453655, 0.04515145115794216, 0.8604396115338614],
            7: [0.000054784584815979276, 0.9207645170021637, 0.2892372553652326, 0.210550923464145, 0.7293706618851845],
            9: [0.0000704373233348305, 0.18384009328849618, 0.8004478997552991, 0.12785118731104358, 0.794905136709523]
        ]
        for (seed, values) in golden {
            var rng = SeededRandom(seed: seed)
            for expected in values { XCTAssertEqual(rng.next(), expected, accuracy: 1e-15, "seed \(seed)") }
        }
    }

    // MARK: Pages

    func testPageSizeFollowsDensity() {
        XCTAssertEqual(PageRenderer.pixelSize(density: 1).w, 1280)
        XCTAssertEqual(PageRenderer.pixelSize(density: 1).h, 1820)
        XCTAssertEqual(PageRenderer.pixelSize(density: 1.5).w, 1920)
        XCTAssertEqual(PageRenderer.pixelSize(density: 1.5).h, 2730)
        let image = PageRenderer.draw(nil, options()).image
        XCTAssertEqual(image.width, 1280)
        XCTAssertEqual(image.height, 1820)
        let big = PageRenderer.draw(nil, options(density: 1.5)).image
        XCTAssertEqual(big.width, 1920)
        XCTAssertEqual(big.height, 2730)
    }

    func testBlankPageIsPaperColour() {
        let (image, hits) = PageRenderer.draw(nil, options())
        XCTAssertTrue(hits.isEmpty)
        let data = pixels(image)
        let p = pixel(data, image, 640, 910)
        let paper = PagePalette.history.paper
        XCTAssertEqual(Double(p.r), paper.r * 255, accuracy: 12)
        XCTAssertEqual(Double(p.g), paper.g * 255, accuracy: 12)
        XCTAssertEqual(Double(p.b), paper.b * 255, accuracy: 12)
    }

    func testPageWithTextHasInk() throws {
        let phys = try physical([.paragraph("some words on a page"), .keyPoint(label: "Note", text: "key")])
        let (image, _) = PageRenderer.draw(phys, options())
        let data = pixels(image)
        var dark = 0
        for i in stride(from: 0, to: data.count, by: 4) where Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2]) < 200 { dark += 1 }
        XCTAssertGreaterThan(dark, 2000, "no ink was drawn")
    }

    func testHitsForTermsAndConcealedRecall() throws {
        let phys = try physical([.paragraph("The {{treaty|fez}} was signed in [[1912|e]] by many.")])
        var recall = RecallState(level: .essential)
        recall.setEnabled(true)
        let (_, hits) = PageRenderer.draw(phys, options(recall: recall))
        let terms = hits.filter { if case .term = $0.kind { return true } else { return false } }
        let recalls = hits.filter { if case .recall = $0.kind { return true } else { return false } }
        XCTAssertEqual(terms.count, 1)
        XCTAssertEqual(recalls.count, 1)
        if case .recall(let key, let level) = recalls[0].kind {
            XCTAssertEqual(key, "l/p#0.p.0")
            XCTAssertEqual(level, .essential)
        }
        // Without Magnifying Glass nothing is tappable except the term.
        let (_, plain) = PageRenderer.draw(phys, options())
        XCTAssertEqual(plain.count, 1)
    }

    func testConcealedAnswerIsNotDrawn() throws {
        // Two pages that differ only in the hidden answer (same width): with the answer concealed the bitmaps are identical.
        let a = try physical([.paragraph("Signed in [[1912|e]] by many.")])
        let b = try physical([.paragraph("Signed in [[1956|e]] by many.")])
        var recall = RecallState(level: .essential)
        recall.setEnabled(true)
        let hiddenA = pixels(PageRenderer.draw(a, options(recall: recall)).image)
        let hiddenB = pixels(PageRenderer.draw(b, options(recall: recall)).image)
        XCTAssertEqual(hiddenA, hiddenB, "the concealed answer leaked into the bitmap")
        // Revealed, the two answers are drawn and differ.
        let shownA = pixels(PageRenderer.draw(a, options(recall: recall, revealAll: true)).image)
        let shownB = pixels(PageRenderer.draw(b, options(recall: recall, revealAll: true)).image)
        XCTAssertNotEqual(shownA, shownB)
    }

    func testRevealingATargetChangesThePage() throws {
        let phys = try physical([.paragraph("Signed in [[1912|e]] by many.")])
        var recall = RecallState(level: .essential)
        recall.setEnabled(true)
        let hidden = pixels(PageRenderer.draw(phys, options(recall: recall)).image)
        recall.revealPage(phys.id)
        let shown = pixels(PageRenderer.draw(phys, options(recall: recall)).image)
        XCTAssertNotEqual(hidden, shown)
    }

    // MARK: Covers and desk

    func testCoversHaveExpectedSizes() {
        for subject in ["history", "geography"] {
            let cover = CoverArt.make(subject: subject)
            for image in [cover.color, cover.roughness, cover.metalness, cover.bump] {
                XCTAssertEqual(image.width, 1024)
                XCTAssertEqual(image.height, 1450)
            }
            XCTAssertEqual(cover.endpaper.width, 512)
            XCTAssertEqual(cover.endpaper.height, 512)
        }
        let edge = CoverArt.pageEdge()
        XCTAssertEqual(edge.width, 64)
        XCTAssertEqual(edge.height, 256)
    }

    func testFoilIsMetalAndShinyOnlyWhereItIsDrawn() {
        let cover = CoverArt.make(subject: "history")
        let metal = pixels(cover.metalness)
        let rough = pixels(cover.roughness)
        var foilPixels = 0
        for i in stride(from: 0, to: metal.count, by: 4) where metal[i] > 200 { foilPixels += 1 }
        XCTAssertGreaterThan(foilPixels, 5000)
        XCTAssertLessThan(foilPixels, 1024 * 1450 / 3)
        // Cloth corner: not metal, rough.
        XCTAssertLessThan(Int(metal[(30 * 1024 + 30) * 4]), 10)
        XCTAssertGreaterThan(Int(rough[(30 * 1024 + 30) * 4]), 150)
    }

    func testCoverColourIsGoldWhereTheFoilIsAndClothElsewhere() {
        let cover = CoverArt.make(subject: "history")
        let data = pixels(cover.color)
        // The outer frame line (9 px wide, inset 78) is gold: bright and warm.
        let gold = pixel(data, cover.color, 512, 82)
        XCTAssertGreaterThan(gold.r, 150)
        XCTAssertGreaterThan(gold.r, gold.b + 40)
        // The cloth corner is dark red.
        let cloth = pixel(data, cover.color, 30, 30)
        XCTAssertGreaterThan(cloth.r, cloth.g + 30)
        XCTAssertLessThan(cloth.r, 170)
    }

    func testGeographyCoverIsTealCloth() {
        let cover = CoverArt.make(subject: "geography")
        let data = pixels(cover.color)
        let cloth = pixel(data, cover.color, 30, 30)
        XCTAssertGreaterThan(cloth.b, cloth.r)
        XCTAssertGreaterThan(cloth.g, cloth.r)
    }

    func testDeskTexturesHaveExpectedSizesAndGrain() {
        let wood = DeskArt.wood()
        XCTAssertEqual(wood.map.width, 1024)
        XCTAssertEqual(wood.bump.height, 1024)
        let colour = pixels(wood.map)
        // Warm brown planks: red above blue everywhere sampled.
        for (x, y) in [(100, 100), (400, 700), (900, 300)] {
            let p = pixel(colour, wood.map, x, y)
            XCTAssertGreaterThan(p.r, p.b + 30)
        }
        let felt = DeskArt.felt()
        XCTAssertEqual(felt.width, 256)
        let tile = pixels(felt)
        XCTAssertGreaterThan(Int(tile[0]), 200, "the felt tile is mostly white")
    }

    func testTexturesAreDeterministic() {
        XCTAssertEqual(pixels(DeskArt.felt()), pixels(DeskArt.felt()))
        XCTAssertEqual(pixels(CoverArt.pageEdge()), pixels(CoverArt.pageEdge()))
    }
}
