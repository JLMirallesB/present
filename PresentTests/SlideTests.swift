import XCTest

final class SlideTests: XCTestCase {

    // MARK: - What a slide renders

    func testPlainURLIsAWebSlide() {
        XCTAssertEqual(Slide(url: "https://jlmirall.es").content, .web("https://jlmirall.es"))
    }

    func testBareHostGetsAnHTTPSScheme() {
        XCTAssertEqual(Slide(url: "jlmirall.es").content, .web("https://jlmirall.es"))
    }

    func testImageExtensionsAreDetected() {
        for ext in ["png", "gif", "jpg", "jpeg", "webp", "svg", "PNG", "JPeG"] {
            XCTAssertEqual(
                Slide(url: "https://example.com/a.\(ext)").content,
                .image("https://example.com/a.\(ext)"),
                "\(ext) should render as an image"
            )
        }
    }

    /// A query string must not hide the extension.
    func testImageDetectionIgnoresQueryStrings() {
        XCTAssertEqual(
            Slide(url: "https://example.com/a.png?v=2").content,
            .image("https://example.com/a.png?v=2")
        )
    }

    func testAPageThatMerelyMentionsAnImageIsNotAnImage() {
        XCTAssertEqual(
            Slide(url: "https://example.com/png-guide").content,
            .web("https://example.com/png-guide")
        )
    }

    func testTextSlideBeatsWhateverIsInTheURLField() {
        let slide = Slide(url: "https://example.com/a.png", text: "# Hola")
        XCTAssertEqual(slide.content, .text("# Hola"))
        XCTAssertTrue(slide.isTextSlide)
    }

    // MARK: - Sidebar label

    func testDisplayNameWins() {
        XCTAssertEqual(Slide(url: "https://a.test", displayName: "Portada").label, "Portada")
    }

    func testBlankDisplayNameFallsBackToTheURL() {
        XCTAssertEqual(Slide(url: "https://a.test", displayName: "   ").label, "https://a.test")
    }

    func testUnnamedTextSlideIsLabelledByItsFirstHeading() {
        XCTAssertEqual(Slide.textSlide("\n\n# El pulpo en el vaso\n\ntexto").label, "El pulpo en el vaso")
    }

    func testEmptyTextSlideStillHasALabel() {
        XCTAssertEqual(Slide.textSlide("").label, "Empty text slide")
    }

    // MARK: - Codable

    func testOlderSlidesWithoutATextFieldStillDecode() throws {
        let json = #"{"id":"\#(UUID().uuidString)","url":"https://a.test"}"#
        let slide = try JSONDecoder().decode(Slide.self, from: Data(json.utf8))
        XCTAssertNil(slide.text)
        XCTAssertNil(slide.displayName)
        XCTAssertEqual(slide.url, "https://a.test")
    }

    func testRoundTripsThroughJSON() throws {
        let original = Slide(url: "https://a.test", displayName: "A", text: "# Hola\nmundo")
        let decoded = try JSONDecoder().decode(Slide.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.displayName, original.displayName)
    }
}
