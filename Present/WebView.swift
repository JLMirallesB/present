import SwiftUI
import WebKit

/// Keeps a small set of live web views, so moving to the next slide shows a
/// page that has already loaded instead of a white rectangle filling in.
///
/// Views are keyed by content, which also means a slide you come back to is
/// still where you left it — same scroll position, same state.
@MainActor
final class SlideWebViewPool {
    /// Current slide plus the neighbours we preload. Small on purpose: each
    /// WKWebView is a live web process.
    private static let capacity = 5

    private var cache: [SlideContent: WKWebView] = [:]
    /// Most recently used last, so eviction can drop from the front.
    private var order: [SlideContent] = []

    /// A web view set up the way every slide wants it.
    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Off by default in WKWebView: without it `requestFullscreen()` is
        // refused, so the fullscreen button on an embedded video — an X post,
        // a YouTube embed — does nothing at all.
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        // Slides sit on black; without this the gap before first paint is white.
        webView.underPageBackgroundColor = .black
        return webView
    }

    func view(for content: SlideContent) -> WKWebView {
        touch(content)
        if let existing = cache[content] { return existing }

        let webView = Self.makeWebView()
        load(content, into: webView)
        cache[content] = webView
        return webView
    }

    /// Loads pages we are about to need, off-screen.
    func preload(_ contents: [SlideContent]) {
        for content in contents where cache[content] == nil {
            let webView = Self.makeWebView()
            // Give it a real size, or layout-sensitive pages render wrong when
            // they finally appear.
            webView.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
            load(content, into: webView)
            cache[content] = webView
            order.insert(content, at: max(0, order.count - 1))
        }
        evictIfNeeded()
    }

    func setPageZoom(_ zoom: Double, for content: SlideContent) {
        guard let webView = cache[content] else { return }
        // Images are letterboxed by their wrapper page; zoom would only fight
        // with object-fit.
        webView.pageZoom = content.isImage ? 1.0 : zoom
    }

    func scrollVisible(_ content: SlideContent, by dy: Double) {
        cache[content]?.evaluateJavaScript("window.scrollBy(0, \(dy));", completionHandler: nil)
    }

    private func load(_ content: SlideContent, into webView: WKWebView) {
        switch content {
        case .web(let address):
            guard let url = URL(string: address) else { return }
            webView.load(URLRequest(url: url))
        case .image(let address):
            webView.loadHTMLString(Self.imagePageHTML(for: address), baseURL: nil)
        case .text(let markdown):
            webView.loadHTMLString(MarkdownSlide.html(for: markdown), baseURL: nil)
        }
    }

    private func touch(_ content: SlideContent) {
        order.removeAll { $0 == content }
        order.append(content)
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while order.count > Self.capacity {
            let oldest = order.removeFirst()
            cache[oldest]?.removeFromSuperview()
            cache.removeValue(forKey: oldest)
        }
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
}

/// Shows one slide, and quietly gets the neighbours ready.
struct WebView: NSViewRepresentable {
    let content: SlideContent
    /// Slides to have loaded before they are asked for.
    var neighbours: [SlideContent] = []
    var pageZoom: Double = 1.0
    /// Scroll asked for by the remote. Applied once per new sequence number.
    var scroll = ScrollRequest()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        // Whatever the remote asked for before this view existed is not ours.
        context.coordinator.lastScrollSequence = scroll.sequence
        update(container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        update(container, coordinator: context.coordinator)
    }

    private func update(_ container: NSView, coordinator: Coordinator) {
        let pool = coordinator.pool
        coordinator.visible = content

        let webView = pool.view(for: content)
        if webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
        pool.setPageZoom(pageZoom, for: content)
        pool.preload(neighbours)

        if scroll.sequence != coordinator.lastScrollSequence {
            coordinator.lastScrollSequence = scroll.sequence
            pool.scrollVisible(content, by: scroll.dy)
        }
    }

    /// Lays out its single web view; `autoresizingMask` alone loses the size
    /// when the view is swapped in at a different size than it was created.
    private final class ContainerView: NSView {
        override func layout() {
            super.layout()
            subviews.first?.frame = bounds
        }
    }

    @MainActor
    class Coordinator {
        let pool = SlideWebViewPool()
        var visible: SlideContent?
        var lastScrollSequence = 0
    }
}
