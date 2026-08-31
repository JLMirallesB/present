import XCTest
import AppKit

final class PresentationKeymapTests: XCTestCase {

    private func command(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> PresentationCommand? {
        PresentationKeymap.command(for: keyCode, modifiers: modifiers)
    }

    /// Presentation clickers send Page Up and Page Down. Without these, a
    /// physical remote does nothing at all.
    func testClickerKeysNavigate() {
        XCTAssertEqual(command(121), .next)      // Page Down
        XCTAssertEqual(command(116), .previous)  // Page Up
    }

    func testArrowKeysNavigate() {
        XCTAssertEqual(command(124), .next)      // Right
        XCTAssertEqual(command(123), .previous)  // Left
    }

    /// Up and Down must reach the page, or a slide that is a long article
    /// cannot be scrolled from the keyboard.
    func testVerticalArrowsAreLeftToThePage() {
        XCTAssertNil(command(126))  // Up
        XCTAssertNil(command(125))  // Down
    }

    func testCommandArrowsNavigateAsDocumented() {
        XCTAssertEqual(command(126, .command), .previous)
        XCTAssertEqual(command(125, .command), .next)
    }

    /// Same reason as the vertical arrows: space scrolls long pages.
    func testSpaceIsLeftToThePage() {
        XCTAssertNil(command(49))
        XCTAssertNil(command(49, .shift))
    }

    func testJumpToEnds() {
        XCTAssertEqual(command(115), .first)  // Home
        XCTAssertEqual(command(119), .last)   // End
    }

    func testBlackoutAndExit() {
        XCTAssertEqual(command(11), .toggleBlackout)  // B
        XCTAssertEqual(command(53), .exit)            // Escape
    }

    // MARK: - Zoom

    /// Regression: `case 24, 69 where cmd` applied the guard to the last
    /// pattern only, so a bare "=" or "-" changed the zoom. Typing into a form
    /// on a slide moved the page out from under you.
    func testZoomNeedsCommand() {
        XCTAssertNil(command(24), "bare = must not zoom")
        XCTAssertNil(command(27), "bare - must not zoom")
        XCTAssertNil(command(69), "bare keypad + must not zoom")
        XCTAssertNil(command(78), "bare keypad - must not zoom")

        XCTAssertEqual(command(24, .command), .zoomIn)
        XCTAssertEqual(command(27, .command), .zoomOut)
        XCTAssertEqual(command(69, .command), .zoomIn)
        XCTAssertEqual(command(78, .command), .zoomOut)
        XCTAssertEqual(command(29, .command), .zoomReset)
    }

    func testUnmappedKeysFallThrough() {
        for keyCode: UInt16 in [0, 1, 12, 36, 48, 96, 200] {
            XCTAssertNil(command(keyCode), "key \(keyCode) should reach the page")
        }
    }
}
