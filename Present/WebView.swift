import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    /// What to show. `SlideContent` is Equatable, so SwiftUI only pushes an
    /// update when the slide actually changes.
    let content: SlideContent
    var pageZoom: Double = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.startListening()
        apply(to: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        apply(to: webView, coordinator: context.coordinator)
    }

    private func apply(to webView: WKWebView, coordinator: Coordinator) {
        switch content {
        case .web(let address):
            coordinator.loadedContent = nil
            webView.pageZoom = pageZoom
            guard let parsed = URL(string: address) else { return }
            if webView.url != parsed {
                webView.load(URLRequest(url: parsed))
            }

        case .image(let address):
            // Images are letterboxed by the wrapper page, so page zoom would
            // only fight with `object-fit`.
            webView.pageZoom = 1.0
            loadOnce(content, in: webView, coordinator: coordinator) {
                Self.imagePageHTML(for: address)
            }

        case .text(let markdown):
            // Text slides honour zoom: handy for resizing mid-talk.
            webView.pageZoom = pageZoom
            loadOnce(content, in: webView, coordinator: coordinator) {
                MarkdownSlide.html(for: markdown)
            }
        }
    }

    /// Generated pages have no URL of their own, so `webView.url` cannot tell
    /// us whether they are already loaded. Track it on the coordinator instead
    /// and avoid reloading (and flashing) on every zoom change.
    private func loadOnce(
        _ content: SlideContent,
        in webView: WKWebView,
        coordinator: Coordinator,
        html: () -> String
    ) {
        guard coordinator.loadedContent != content else { return }
        coordinator.loadedContent = content
        webView.loadHTMLString(html(), baseURL: nil)
    }

    private static func imagePageHTML(for address: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>*{margin:0;padding:0;overflow:hidden}
        body{background:#000;display:flex;align-items:center;justify-content:center;width:100vw;height:100vh}
        img{max-width:100vw;max-height:100vh;object-fit:contain}</style>
        </head><body><img src="\(MarkdownSlide.escapeHTML(address))"></body></html>
        """
    }

    class Coordinator {
        weak var webView: WKWebView?
        /// The generated content currently displayed, if any.
        var loadedContent: SlideContent?
        private var observer: NSObjectProtocol?

        func startListening() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .remoteScroll, object: nil, queue: .main
            ) { [weak self] notification in
                guard let dy = notification.userInfo?["dy"] as? Double,
                      let webView = self?.webView else { return }
                webView.evaluateJavaScript("window.scrollBy(0, \(dy));", completionHandler: nil)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
