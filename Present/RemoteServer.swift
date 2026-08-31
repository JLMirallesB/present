import Foundation
import Network

extension Notification.Name {
    static let remotePlay = Notification.Name("remotePlay")
    static let remoteStop = Notification.Name("remoteStop")
    static let remoteScroll = Notification.Name("remoteScroll")
    static let showRemoteInfo = Notification.Name("showRemoteInfo")
}

/// A tiny HTTP server that serves a phone-friendly remote control.
///
/// It listens on every interface, because the point is to drive the talk from
/// a phone on the same network. That makes two things mandatory:
///
///   * **A token.** Without one, every page you visit in any browser on this
///     machine could advance your slides with `fetch("http://localhost:9123/next")`.
///     The response would be blocked by CORS, but the side effect would already
///     have happened. The token is generated per launch, never persisted, and
///     required by every endpoint.
///
///   * **A Host check.** A hostile site can point its own domain at 127.0.0.1
///     (DNS rebinding) to get same-origin access. Such a request still carries
///     that domain in its Host header, so requiring a literal IP or localhost
///     turns it away.
@Observable
@MainActor
final class RemoteServer {
    static let port: NWEndpoint.Port = 9123

    private var listener: NWListener?
    private var state: PresentationState?

    /// Fresh per launch. Anyone holding it can drive the presentation, which
    /// is exactly what the phone in your pocket is meant to do.
    let token: String = RemoteServer.makeToken()

    private(set) var isRunning = false
    private(set) var lastError: String?

    private static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<4)
            .map { _ in String(format: "%08x", generator.next(upperBound: UInt32.max)) }
            .joined()
    }

    // MARK: - Lifecycle

    func start(state: PresentationState) {
        self.state = state
        guard listener == nil else { return }
        do {
            listener = try NWListener(using: .tcp, on: Self.port)
        } catch {
            lastError = "Port \(Self.port) is not available."
            print("RemoteServer: failed to create listener: \(error)")
            return
        }
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.handle(connection) }
        }
        listener?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }
        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func toggle(state: PresentationState) {
        if isRunning || listener != nil { stop() } else { start(state: state) }
    }

    /// The address to type, or scan, on the phone. Falls back to localhost when
    /// no local network address can be found.
    var remoteURL: String {
        "http://\(Self.localAddress() ?? "localhost"):\(Self.port)/?t=\(token)"
    }

    // MARK: - Connections

    private nonisolated static let maxRequestBytes = 16 * 1024

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, accumulated: Data())
    }

    /// A request is not guaranteed to arrive in one packet, so read until the
    /// end of the headers. This server only answers GET, so there is no body.
    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            // Everything below touches actor-isolated state, so hop first.
            Task { @MainActor in
                guard let self, error == nil else {
                    connection.cancel()
                    return
                }
                var buffer = accumulated
                if let data { buffer.append(data) }

                guard buffer.count <= Self.maxRequestBytes else {
                    self.reply(Response(status: "431 Request Header Fields Too Large"), on: connection)
                    return
                }
                guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if isComplete {
                        connection.cancel()
                    } else {
                        self.receive(on: connection, accumulated: buffer)
                    }
                    return
                }

                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.reply(self.route(head), on: connection)
            }
        }
    }

    private func reply(_ response: Response, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    struct Response {
        var status: String = "200 OK"
        var contentType = "application/json"
        var body = "{\"status\":\"error\"}"

        static func json(_ object: [String: Any]) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                ?? Data("{}".utf8)
            return Response(body: String(decoding: data, as: UTF8.self))
        }

        static let ok = Response(body: "{\"status\":\"ok\"}")

        func serialized() -> Data {
            let bytes = Data(body.utf8)
            let head = """
            HTTP/1.1 \(status)\r
            Content-Type: \(contentType)\r
            Content-Length: \(bytes.count)\r
            Cache-Control: no-store\r
            X-Content-Type-Options: nosniff\r
            Connection: close\r
            \r

            """
            return Data(head.utf8) + bytes
        }
    }

    /// Split out from the networking so it can be tested directly.
    func route(_ head: String) -> Response {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else {
            return Response(status: "400 Bad Request")
        }
        guard parts[0] == "GET" else {
            return Response(status: "405 Method Not Allowed")
        }

        let host = Self.headerValue("Host", in: lines)
        guard Self.isLiteralAddress(host) else {
            // DNS rebinding: the request reached us, but under someone's domain.
            return Response(status: "403 Forbidden")
        }

        let target = String(parts[1])
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let query = Self.parseQuery(target)

        guard let supplied = query["t"], Self.constantTimeEquals(supplied, token) else {
            return unauthorized(for: path)
        }

        switch path {
        case "/", "/index.html":
            return Response(contentType: "text/html; charset=utf-8", body: Self.page(token: token))
        case "/next":
            state?.goToNext()
            return .ok
        case "/prev":
            state?.goToPrevious()
            return .ok
        case "/play":
            NotificationCenter.default.post(name: .remotePlay, object: nil)
            return .ok
        case "/stop":
            NotificationCenter.default.post(name: .remoteStop, object: nil)
            return .ok
        case "/zoomin":
            state?.zoomIn()
            return .ok
        case "/zoomout":
            state?.zoomOut()
            return .ok
        case "/scroll":
            if let dy = query["dy"].flatMap(Double.init) {
                NotificationCenter.default.post(name: .remoteScroll, object: nil, userInfo: ["dy": dy])
            }
            return .ok
        case "/status":
            return .json([
                "slide": (state?.currentIndex ?? 0) + 1,
                "total": state?.slides.count ?? 0,
                "presenting": state?.isPresenting ?? false,
                "label": state?.currentSlide?.label ?? "",
                "url": state?.currentSlide?.url ?? "",
            ])
        default:
            return Response(status: "404 Not Found")
        }
    }

    /// A browser landing here without the token gets an explanation, not a 404:
    /// it is almost always the person who typed the address by hand.
    private func unauthorized(for path: String) -> Response {
        if path == "/" || path == "/index.html" {
            return Response(
                status: "401 Unauthorized",
                contentType: "text/html; charset=utf-8",
                body: Self.tokenMissingPage
            )
        }
        return Response(status: "401 Unauthorized")
    }

    // MARK: - Request helpers

    static func headerValue(_ name: String, in lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines.dropFirst() where line.lowercased().hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func parseQuery(_ target: String) -> [String: String] {
        guard let separator = target.firstIndex(of: "?") else { return [:] }
        let query = String(target[target.index(after: separator)...])
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let bits = pair.split(separator: "=", maxSplits: 1)
            guard let name = bits.first else { continue }
            let value = bits.count > 1 ? String(bits[1]) : ""
            result[String(name)] = value.removingPercentEncoding ?? value
        }
        return result
    }

    /// True for `localhost`, an IPv4 literal or a bracketed IPv6 literal,
    /// with or without a port. False for any DNS name — which is the point.
    static func isLiteralAddress(_ host: String?) -> Bool {
        guard var host, !host.isEmpty else { return false }

        if host.hasPrefix("[") {                       // [::1]:9123
            guard let end = host.firstIndex(of: "]") else { return false }
            host = String(host[host.index(after: host.startIndex)..<end])
            var parsed = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &parsed) == 1 }
        }
        if let colon = host.lastIndex(of: ":") {       // 192.168.1.5:9123
            host = String(host[..<colon])
        }
        if host == "localhost" { return true }
        var parsed = in_addr()
        return host.withCString { inet_pton(AF_INET, $0, &parsed) == 1 }
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    /// First non-loopback IPv4 address, which is what the phone needs.
    static func localAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var best: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let name = String(cString: pointer.pointee.ifa_name)
            let host = String(cString: buffer)
            if name == "en0" { return host }   // Wi-Fi first
            if best == nil { best = host }
        }
        return best
    }
}

// MARK: - Served pages

extension RemoteServer {

    static let tokenMissingPage = """
    <!DOCTYPE html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Present Remote</title>
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
           background:#1a1a2e;color:#eee;display:flex;align-items:center;
           justify-content:center;height:100dvh;margin:0;padding:24px;text-align:center}
      div{max-width:30em}
      h1{font-size:1.3rem;margin:0 0 .6em}
      p{opacity:.7;line-height:1.5;margin:0}
    </style></head>
    <body><div>
      <h1>This link is missing its key</h1>
      <p>In Present, choose <strong>Presentation &rsaquo; Remote Control</strong>
         and scan the code shown there, or open the full address it gives you.</p>
    </div></body></html>
    """

    static func page(token: String) -> String {
        htmlPage.replacingOccurrences(of: "__TOKEN__", with: token)
    }

    static let htmlPage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <meta name="referrer" content="no-referrer">
    <title>Present Remote</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
        background: #1a1a2e; color: #eee;
        display: flex; flex-direction: column; align-items: center;
        height: 100dvh; padding: 20px; gap: 16px;
        -webkit-user-select: none; user-select: none;
      }
      #status { font-size: 1.6rem; font-weight: 600; text-align: center; min-height: 2em; }
      #label { font-size: 0.85rem; opacity: 0.45; word-break: break-word; text-align: center; max-width: 90vw; }
      .nav-row { display: flex; gap: 16px; width: 100%; max-width: 400px; }
      button {
        flex: 1; padding: 24px 10px; font-size: 1.5rem; font-weight: 600;
        border: none; border-radius: 14px; cursor: pointer;
        transition: transform 0.1s, opacity 0.1s;
        min-height: 80px;
      }
      button:active { transform: scale(0.95); opacity: 0.8; }
      .btn-prev { background: #16213e; color: #e94560; }
      .btn-next { background: #16213e; color: #53d8fb; }
      .btn-play { background: #0f3460; color: #53d8fb; }
      .btn-stop { background: #e94560; color: #fff; }
      .play-row { display: flex; gap: 16px; width: 100%; max-width: 400px; flex: 1; min-height: 0; }
      .play-row button { flex: 1; min-height: 0; height: auto; }
      .scroll-strip {
        width: 50px; flex-shrink: 0; background: #16213e; border-radius: 14px;
        display: flex; align-items: center; justify-content: center;
        color: #555; font-size: 1.2rem; touch-action: none; cursor: grab;
      }
      .scroll-strip:active { cursor: grabbing; background: #1a2740; }
      .zoom-row { display: flex; gap: 16px; width: 100%; max-width: 400px; }
      .btn-zoom { background: #16213e; color: #aaa; font-size: 1.3rem; min-height: 60px; }
      html { touch-action: manipulation; }
    </style>
    </head>
    <body>
      <div id="status">Connecting...</div>
      <div class="nav-row">
        <button class="btn-prev" onclick="send('/prev')">&lsaquo; Prev</button>
        <button class="btn-next" onclick="send('/next')">Next &rsaquo;</button>
      </div>
      <div class="play-row">
        <button id="playBtn" class="btn-play" onclick="togglePlay()">&#9654; Start</button>
        <div class="scroll-strip" id="scrollStrip">&#8597;</div>
      </div>
      <div class="zoom-row">
        <button class="btn-zoom" onclick="send('/zoomout')">A-</button>
        <button class="btn-zoom" onclick="send('/zoomin')">A+</button>
      </div>
      <div id="label"></div>
      <script>
        // Handed over by the app when it served this page, and kept out of the
        // address bar afterwards so it does not end up in screenshots.
        const TOKEN = "__TOKEN__";
        history.replaceState(null, "", "/");

        let presenting = false;
        function call(path, params) {
          const query = new URLSearchParams(params || {});
          query.set('t', TOKEN);
          return fetch(path + '?' + query.toString());
        }
        function send(path) { call(path).catch(() => {}); }
        function togglePlay() { send(presenting ? '/stop' : '/play'); }

        function poll() {
          call('/status').then(r => r.json()).then(d => {
            document.getElementById('status').textContent = 'Slide ' + d.slide + ' / ' + d.total;
            document.getElementById('label').textContent = d.label || d.url || '';
            presenting = d.presenting;
            const btn = document.getElementById('playBtn');
            btn.textContent = presenting ? '\\u25A0 Stop' : '\\u25B6 Start';
            btn.className = presenting ? 'btn-stop' : 'btn-play';
          }).catch(() => {
            document.getElementById('status').textContent = 'Disconnected';
          });
        }
        setInterval(poll, 1000);
        poll();

        const strip = document.getElementById('scrollStrip');
        let lastY = null;
        let pendingDy = 0;
        let sendTimer = null;
        function flushScroll() {
          if (pendingDy !== 0) {
            call('/scroll', {dy: Math.round(pendingDy)}).catch(() => {});
            pendingDy = 0;
          }
          sendTimer = null;
        }
        strip.addEventListener('touchstart', e => {
          e.preventDefault();
          lastY = e.touches[0].clientY;
          pendingDy = 0;
        }, {passive: false});
        strip.addEventListener('touchmove', e => {
          e.preventDefault();
          const y = e.touches[0].clientY;
          if (lastY !== null) {
            pendingDy += (y - lastY) * 2;
            lastY = y;
            if (!sendTimer) { sendTimer = setTimeout(flushScroll, 50); }
          }
        }, {passive: false});
        strip.addEventListener('touchend', () => {
          lastY = null;
          flushScroll();
          if (sendTimer) { clearTimeout(sendTimer); sendTimer = null; }
        });
      </script>
    </body>
    </html>
    """
}
