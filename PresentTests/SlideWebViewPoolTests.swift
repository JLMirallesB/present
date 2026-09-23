import XCTest
import WebKit

@MainActor
final class SlideWebViewPoolTests: XCTestCase {

    /// WKWebView refuses `requestFullscreen()` unless the preference is on, and
    /// that is what the fullscreen button on an embedded video calls.
    func testSlidesCanGoFullscreen() async throws {
        let pool = SlideWebViewPool()
        let webView = pool.view(for: .text("hola"))
        try await waitForLoad(of: webView)

        let enabled = try await webView.evaluateJavaScript("document.fullscreenEnabled") as? Bool
        XCTAssertEqual(enabled, true)
    }

    private func waitForLoad(of webView: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(5)
        while webView.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(webView.isLoading, "the slide never finished loading")
    }
}
