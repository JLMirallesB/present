import XCTest

final class MarkdownSlideTests: XCTestCase {

    // MARK: - Escaping
    //
    // The whole reason for not reusing kcarnold's renderer: it interpolates
    // slide text straight into HTML.

    func testAngleBracketsAndAmpersandsAreEscaped() {
        let html = MarkdownSlide.inline("if a < b && c > d")
        XCTAssertEqual(html, "if a &lt; b &amp;&amp; c &gt; d")
    }

    func testMarkupInSlideTextCannotInjectHTML() {
        let html = MarkdownSlide.html(for: "<script>alert('x')</script>")
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    // MARK: - Inline markup

    func testBoldAndItalic() {
        XCTAssertEqual(MarkdownSlide.inline("**muy** *importante*"),
                       "<strong>muy</strong> <em>importante</em>")
    }

    func testUnderscoreItalic() {
        XCTAssertEqual(MarkdownSlide.inline("_así_"), "<em>así</em>")
    }

    /// Regression against kcarnold's renderer, whose italic rule mangles this.
    func testSnakeCaseIsNotTreatedAsItalic() {
        XCTAssertEqual(MarkdownSlide.inline("current_set_id"), "current_set_id")
    }

    func testAsterisksInsideCodeAreLeftAlone() {
        XCTAssertEqual(MarkdownSlide.inline("`a * b * c`"), "<code>a * b * c</code>")
    }

    func testBoldInsideAHeadingWorks() {
        XCTAssertTrue(MarkdownSlide.html(for: "# Un **título**").contains("<h1>Un <strong>título</strong></h1>"))
    }

    // MARK: - Block structure

    func testBlankLinesSeparateBlocks() {
        XCTAssertEqual(MarkdownSlide.blocks(from: "uno\n\n\ndos\n"), [["uno"], ["dos"]])
    }

    func testHeadingLevels() {
        for (markdown, tag) in [("# a", "h1"), ("## a", "h2"), ("### a", "h3")] {
            XCTAssertTrue(MarkdownSlide.html(for: markdown).contains("<\(tag)>a</\(tag)>"))
        }
    }

    func testBulletsBecomeAList() {
        let html = MarkdownSlide.html(for: "- uno\n- dos")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>uno</li>"))
        XCTAssertTrue(html.contains("<li>dos</li>"))
    }

    func testConsecutiveLinesKeepTheirBreaks() {
        XCTAssertTrue(MarkdownSlide.html(for: "uno\ndos").contains("<p>uno<br>dos</p>"))
    }

    func testHorizontalRule() {
        XCTAssertTrue(MarkdownSlide.html(for: "---").contains("<hr>"))
    }

    func testEmptyMarkdownStillProducesAValidPage() {
        let html = MarkdownSlide.html(for: "")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("</html>"))
    }

    /// A hash that is not a heading marker stays literal.
    func testHashWithoutASpaceIsNotAHeading() {
        XCTAssertTrue(MarkdownSlide.html(for: "#hashtag").contains("<p>#hashtag</p>"))
    }
}
