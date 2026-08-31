import XCTest

@MainActor
final class RemoteServerTests: XCTestCase {

    private func makeServer() -> RemoteServer { RemoteServer() }

    /// A well-formed request, so each test can vary the one thing it is about.
    private func request(
        _ target: String,
        method: String = "GET",
        host: String = "192.168.1.5:9123"
    ) -> String {
        "\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: test"
    }

    // MARK: - The token

    func testCommandsAreRejectedWithoutAToken() {
        let server = makeServer()
        for path in ["/next", "/prev", "/play", "/stop", "/zoomin", "/zoomout", "/scroll", "/status"] {
            XCTAssertEqual(server.route(request(path)).status, "401 Unauthorized", "\(path) must require a token")
        }
    }

    func testCommandsAreRejectedWithTheWrongToken() {
        let server = makeServer()
        XCTAssertEqual(server.route(request("/next?t=deadbeef")).status, "401 Unauthorized")
    }

    func testCommandsAreAcceptedWithTheRightToken() {
        let server = makeServer()
        XCTAssertEqual(server.route(request("/next?t=\(server.token)")).status, "200 OK")
    }

    /// This is the whole point: a page you visit in any browser knows the port
    /// but not the token, so it cannot drive the presentation.
    func testAnotherOriginCannotAdvanceTheSlides() {
        let server = makeServer()
        let state = PresentationState(
            storeURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).json"),
            defaults: UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        )
        state.addSlide(Slide(url: "a"))
        state.addSlide(Slide(url: "b"))
        server.start(state: state)
        defer { server.stop() }

        _ = server.route(request("/next", host: "localhost:9123"))
        XCTAssertEqual(state.currentIndex, 0, "no token, no movement")

        _ = server.route(request("/next?t=\(server.token)"))
        XCTAssertEqual(state.currentIndex, 1)
    }

    func testEveryLaunchGetsADifferentToken() {
        XCTAssertNotEqual(makeServer().token, makeServer().token)
        XCTAssertEqual(makeServer().token.count, 32)
    }

    func testTheServedPageCarriesTheToken() {
        let server = makeServer()
        let response = server.route(request("/?t=\(server.token)"))
        XCTAssertEqual(response.status, "200 OK")
        XCTAssertTrue(response.contentType.hasPrefix("text/html"))
        XCTAssertTrue(response.body.contains(server.token))
        XCTAssertFalse(response.body.contains("__TOKEN__"), "placeholder must be substituted")
    }

    /// Someone typing the bare address should be told what to do, not 404'd.
    func testTheBarePageExplainsItself() {
        let response = makeServer().route(request("/"))
        XCTAssertEqual(response.status, "401 Unauthorized")
        XCTAssertTrue(response.body.contains("missing its key"))
    }

    // MARK: - DNS rebinding

    func testRequestsUnderADomainNameAreRefused() {
        let server = makeServer()
        for host in ["evil.example.com", "evil.example.com:9123", "present.local"] {
            XCTAssertEqual(
                server.route(request("/next?t=\(server.token)", host: host)).status,
                "403 Forbidden",
                "\(host) is a DNS name and must be refused even with a valid token"
            )
        }
    }

    func testLiteralAddressesAreAccepted() {
        for host in ["localhost", "localhost:9123", "127.0.0.1", "192.168.1.5:9123", "[::1]:9123", "[::1]"] {
            XCTAssertTrue(RemoteServer.isLiteralAddress(host), "\(host) should be accepted")
        }
    }

    func testDomainNamesAreNotLiteralAddresses() {
        for host in ["example.com", "a.b.c:80", "", "999.999.999.999", "[notanaddress]"] {
            XCTAssertFalse(RemoteServer.isLiteralAddress(host), "\(host) should be refused")
        }
        XCTAssertFalse(RemoteServer.isLiteralAddress(nil))
    }

    func testAMissingHostHeaderIsRefused() {
        let server = makeServer()
        let raw = "GET /next?t=\(server.token) HTTP/1.1\r\nUser-Agent: test"
        XCTAssertEqual(server.route(raw).status, "403 Forbidden")
    }

    // MARK: - Request handling

    func testOnlyGETIsAllowed() {
        let server = makeServer()
        for method in ["POST", "PUT", "DELETE", "HEAD"] {
            XCTAssertEqual(
                server.route(request("/next?t=\(server.token)", method: method)).status,
                "405 Method Not Allowed"
            )
        }
    }

    func testGarbageRequestsDoNotCrash() {
        let server = makeServer()
        XCTAssertEqual(server.route("").status, "400 Bad Request")
        XCTAssertEqual(server.route("GET").status, "400 Bad Request")
    }

    func testUnknownPathsAre404() {
        let server = makeServer()
        XCTAssertEqual(server.route(request("/../../etc/passwd?t=\(server.token)")).status, "404 Not Found")
    }

    func testQueryParsing() {
        XCTAssertEqual(RemoteServer.parseQuery("/scroll?dy=-42&t=abc"), ["dy": "-42", "t": "abc"])
        XCTAssertEqual(RemoteServer.parseQuery("/next"), [:])
        XCTAssertEqual(RemoteServer.parseQuery("/x?a=one%20two"), ["a": "one two"])
    }

    func testHeaderLookupIsCaseInsensitive() {
        let lines = ["GET / HTTP/1.1", "HOST: 127.0.0.1:9123", "Accept: */*"]
        XCTAssertEqual(RemoteServer.headerValue("Host", in: lines), "127.0.0.1:9123")
        XCTAssertNil(RemoteServer.headerValue("Cookie", in: lines))
    }

    func testConstantTimeComparison() {
        XCTAssertTrue(RemoteServer.constantTimeEquals("abc", "abc"))
        XCTAssertFalse(RemoteServer.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(RemoteServer.constantTimeEquals("abc", "abcd"))
        XCTAssertTrue(RemoteServer.constantTimeEquals("", ""))
    }

    // MARK: - Status payload

    /// Hand-built JSON used to escape only quotes; a backslash or a newline in
    /// a slide label produced a response the phone could not parse.
    func testStatusIsValidJSONForAwkwardLabels() throws {
        let server = makeServer()
        let state = PresentationState(
            storeURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).json"),
            defaults: UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        )
        state.addSlide(Slide(url: #"https://a.test/c:\path"#, displayName: "A \"quoted\"\nname"))
        server.start(state: state)
        defer { server.stop() }

        let body = server.route(request("/status?t=\(server.token)")).body
        let parsed = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["label"] as? String, "A \"quoted\"\nname")
        XCTAssertEqual(parsed?["total"] as? Int, 1)
    }
}
