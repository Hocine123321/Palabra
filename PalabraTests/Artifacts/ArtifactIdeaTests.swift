import XCTest
@testable import Palabra

final class ArtifactIdeaTests: XCTestCase {
    func testIdeasAreUniqueAndFitTheEditor() {
        let ideas = ArtifactIdea.all
        XCTAssertEqual(Set(ideas.map(\.id)).count, ideas.count)
        XCTAssertGreaterThanOrEqual(ideas.count, 4)
        for idea in ideas {
            XCTAssertGreaterThanOrEqual(idea.prompt.count, ArtifactGeneratorLimits.minRequestLength, idea.id)
            XCTAssertLessThanOrEqual(idea.prompt.count, ArtifactDraftModel.maxInput, idea.id)
            XCTAssertFalse(idea.title.isEmpty)
            XCTAssertFalse(idea.subtitle.isEmpty)
            XCTAssertNotEqual(idea.format, .auto, "an idea knows what it is: \(idea.id)")
        }
        XCTAssertTrue(ideas.contains { $0.format == .app })
        XCTAssertTrue(ideas.contains { $0.format == .page })
    }

    func testFormatPrefix() {
        XCTAssertEqual(ArtifactFormat.auto.apply(to: "a table"), "a table")
        XCTAssertTrue(ArtifactFormat.page.apply(to: "a table").hasPrefix("FORMAT: build this as kind \"spec\""))
        XCTAssertTrue(ArtifactFormat.page.apply(to: "a table").hasSuffix("a table"))
        XCTAssertTrue(ArtifactFormat.app.apply(to: "a game").hasPrefix("FORMAT: build this as kind \"app\""))
    }

    func testPrefixAndMaxInputStayUnderTheGeneratorCap() {
        for format in ArtifactFormat.allCases {
            XCTAssertLessThanOrEqual(format.requestPrefix.count + ArtifactDraftModel.maxInput, ArtifactGeneratorLimits.maxRequestLength)
        }
    }

    func testEveryQuickChangeHasARequest() {
        for key in ArtifactQuickChange.all {
            let request = ArtifactQuickChange.request(for: key)
            XCTAssertGreaterThanOrEqual(request.count, ArtifactGeneratorLimits.minRequestLength)
            XCTAssertNotEqual(request, key, "chip text and request differ: \(key)")
        }
        XCTAssertEqual(Set(ArtifactQuickChange.all.map(ArtifactQuickChange.request(for:))).count, ArtifactQuickChange.all.count)
    }
}
