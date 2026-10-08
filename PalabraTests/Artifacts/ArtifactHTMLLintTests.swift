import XCTest
@testable import Palabra

final class ArtifactHTMLLintTests: XCTestCase {
    private func error(_ html: String, file: StaticString = #filePath, line: UInt = #line) -> ArtifactHTMLLintError? {
        if case .failure(let error) = ArtifactHTMLLint.check(html) { return error }
        XCTFail("expected a lint failure", file: file, line: line)
        return nil
    }

    private func isExternal(_ error: ArtifactHTMLLintError?) -> Bool {
        if case .externalResource? = error { return true }
        return false
    }

    func testAcceptsMinimalDocument() {
        XCTAssertEqual(ArtifactHTMLLint.check("  <html><body>x</body></html>\n"), .success("<html><body>x</body></html>"))
    }

    func testRejectsMissingHTMLTag() {
        XCTAssertEqual(error("<div>hello</div>"), .missingHTMLTag)
    }

    func testRejectsExternalScript() {
        XCTAssertTrue(isExternal(error(#"<html><script src="https://x.example/y.js"></script></html>"#)))
        XCTAssertTrue(isExternal(error("<html><script src=http://x.example/y.js></script></html>")))
    }

    func testRejectsExternalLink() {
        XCTAssertTrue(isExternal(error("<html><head><link rel='stylesheet' href='https://x.example/a.css'></head></html>")))
    }

    func testRejectsProtocolRelativeSrc() {
        XCTAssertTrue(isExternal(error(#"<html><img src="//cdn.example/a.png"></html>"#)))
    }

    func testRejectsLocalStorage() {
        XCTAssertEqual(error("<html><script>localStorage.setItem('a','b')</script></html>"), .localStorage)
    }

    func testAllowsDataURIImagesAndInlineScript() {
        let html = #"<html><body><img src="data:image/png;base64,AAAA"><script>var a = "https://not-an-attribute";</script></body></html>"#
        XCTAssertEqual(ArtifactHTMLLint.check(html), .success(html))
    }

    func testRejectsOver65536Bytes() {
        let html = "<html>" + String(repeating: "a", count: ArtifactLimits.maxPayloadBytes) + "</html>"
        XCTAssertEqual(error(html), .tooLarge)
    }

    func testIsCaseInsensitiveOnTags() {
        XCTAssertEqual(ArtifactHTMLLint.check("<HTML><BODY>x</BODY></HTML>"), .success("<HTML><BODY>x</BODY></HTML>"))
        XCTAssertTrue(isExternal(error("<HTML><SCRIPT SRC=HTTP://X.EXAMPLE/Y.JS></SCRIPT></HTML>")))
    }

    func testEveryErrorHasADetail() {
        let errors: [ArtifactHTMLLintError] = [.missingHTMLTag, .externalResource("https://x"), .localStorage, .tooLarge]
        for error in errors { XCTAssertFalse(error.detail.isEmpty) }
    }
}
