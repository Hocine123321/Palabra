import XCTest
@testable import Palabra

final class SentenceTokensTests: XCTestCase {
    func testSplitsOnSpacesAndKeepsPunctuationInTheText() {
        let chunks = SentenceTokens.chunks(of: "¿Cómo estás?")
        XCTAssertEqual(chunks.map(\.text), ["¿Cómo", "estás?"])
        XCTAssertEqual(chunks.map(\.core), ["Cómo", "estás"])
    }

    func testRangesAreUTF16OffsetsIntoTheSentence() {
        let sentence = "El niño come"
        let chunks = SentenceTokens.chunks(of: sentence)
        XCTAssertEqual(chunks.map(\.range), [NSRange(location: 0, length: 2), NSRange(location: 3, length: 4), NSRange(location: 8, length: 4)])
        for chunk in chunks {
            XCTAssertEqual((sentence as NSString).substring(with: chunk.range), chunk.text)
        }
    }

    func testExtraSpacesAndEmptyInput() {
        XCTAssertEqual(SentenceTokens.chunks(of: "a   b").map(\.text), ["a", "b"])
        XCTAssertEqual(SentenceTokens.chunks(of: "  ").count, 0)
        XCTAssertEqual(SentenceTokens.chunks(of: "").count, 0)
    }

    func testALoneSymbolHasNoCore() {
        let chunks = SentenceTokens.chunks(of: "hola — 😀 adiós")
        XCTAssertEqual(chunks.map(\.core), ["hola", "", "", "adiós"])
    }

    func testRangesStayCorrectAfterAnEmoji() {
        let sentence = "😀 sí"
        let chunks = SentenceTokens.chunks(of: sentence)
        XCTAssertEqual(chunks.map(\.text), ["😀", "sí"])
        XCTAssertEqual((sentence as NSString).substring(with: chunks[1].range), "sí")
    }

    func testIsSpokenMatchesTheChunkHoldingTheSpokenCharacter() {
        let chunks = SentenceTokens.chunks(of: "uno dos tres")
        let spoken = NSRange(location: 4, length: 3)
        XCTAssertEqual(chunks.map { SentenceTokens.isSpoken($0, at: spoken) }, [false, true, false])
        XCTAssertEqual(chunks.map { SentenceTokens.isSpoken($0, at: nil) }, [false, false, false])
    }
}
