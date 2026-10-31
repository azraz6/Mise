import XCTest
@testable import Mise

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class WebsiteFetcherTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private func response(_ url: URL, status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        var values = headers
        if values["Content-Type"] == nil { values["Content-Type"] = "text/html; charset=utf-8" }
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: values)!
    }

    func testFetchesHTMLPage() async throws {
        let url = URL(string: "https://example.com/recipe")!
        StubURLProtocol.handler = { request in
            (self.response(request.url!), Data("<html><body>Hello</body></html>".utf8))
        }
        let page = try await WebsiteFetcher(session: session).fetch(url)
        XCTAssertEqual(page.html, "<html><body>Hello</body></html>")
        XCTAssertEqual(page.finalURL.absoluteString, url.absoluteString)
        XCTAssertTrue(page.contentType.contains("text/html"))
    }

    func testMapsHTTPStatus() async {
        let url = URL(string: "https://example.com/missing")!
        StubURLProtocol.handler = { request in
            (self.response(request.url!, status: 404), Data())
        }
        do {
            _ = try await WebsiteFetcher(session: session).fetch(url)
            XCTFail("Expected failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .httpStatus(404))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsNonHTMLContent() async {
        let url = URL(string: "https://example.com/file.pdf")!
        StubURLProtocol.handler = { request in
            (self.response(request.url!, headers: ["Content-Type": "application/pdf"]), Data("%PDF".utf8))
        }
        do {
            _ = try await WebsiteFetcher(session: session).fetch(url)
            XCTFail("Expected failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .unsupportedContent("application/pdf"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsUnsafeInitialURLWithoutNetwork() async {
        do {
            _ = try await WebsiteFetcher(session: session).fetch(URL(string: "http://127.0.0.1/recipe")!)
            XCTFail("Expected failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .invalidInput(.unsafeAddress))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBlocksRedirectToPrivateHost() async {
        let url = URL(string: "https://example.com/recipe")!
        let privateURL = URL(string: "http://127.0.0.1/secret")!
        StubURLProtocol.handler = { request in
            if request.url == url {
                return (self.response(url, status: 302, headers: ["Location": privateURL.absoluteString]), Data())
            }
            return (self.response(request.url!, status: 200), Data("should not load".utf8))
        }
        do {
            _ = try await WebsiteFetcher(session: session).fetch(url)
            XCTFail("Expected redirect to be blocked")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .invalidInput(.unsafeAddress))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFollowsSafeRedirect() async throws {
        let url = URL(string: "https://example.com/old")!
        let final = URL(string: "https://example.com/new")!
        StubURLProtocol.handler = { request in
            if request.url == url {
                return (self.response(url, status: 301, headers: ["Location": final.absoluteString]), Data())
            }
            return (self.response(request.url!), Data("<html><body>Moved</body></html>".utf8))
        }
        let page = try await WebsiteFetcher(session: session).fetch(url)
        XCTAssertEqual(page.finalURL.absoluteString, final.absoluteString)
        XCTAssertTrue(page.html.contains("Moved"))
    }

    func testRejectsOversizedContentLength() async {
        let url = URL(string: "https://example.com/big")!
        StubURLProtocol.handler = { request in
            (self.response(request.url!, headers: [
                "Content-Type": "text/html",
                "Content-Length": String(WebsiteFetcher.maximumBytes + 1)
            ]), Data("<html></html>".utf8))
        }
        do {
            _ = try await WebsiteFetcher(session: session).fetch(url)
            XCTFail("Expected failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .responseTooLarge)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDecodesCharsetDeclaredLatin1() {
        let data = "café".data(using: .isoLatin1)!
        XCTAssertEqual(WebsiteFetcher.decode(data: data, contentType: "text/html; charset=iso-8859-1"), "café")
    }

    func testDecodesFallbackWindows1252() {
        let data = "naïve".data(using: .windowsCP1252)!
        XCTAssertEqual(WebsiteFetcher.decode(data: data, contentType: "text/html"), "naïve")
    }

    func testWebsiteExtractorUsesJSONLD() async throws {
        let url = URL(string: "https://example.com/recipe")!
        let html = """
        <html><head><title>Page Title</title>
        <meta property="og:image" content="https://example.com/cover.jpg"></head>
        <body><script type="application/ld+json">
        {"@type":"Recipe","name":"Structured Soup","recipeIngredient":["1 cup stock"],"recipeInstructions":["Simmer."],"recipeYield":"2"}
        </script></body></html>
        """
        StubURLProtocol.handler = { request in
            (self.response(request.url!), Data(html.utf8))
        }
        let extraction = try await WebsiteRecipeExtractor.extract(
            url: url,
            sourceType: .website,
            fetcher: WebsiteFetcher(session: session)
        )
        XCTAssertEqual(extraction.method, .jsonLD)
        XCTAssertEqual(extraction.drafts.first?.title, "Structured Soup")
        XCTAssertEqual(extraction.drafts.first?.servings, 2)
    }

    func testWebsiteExtractorFallsBackToPageText() async throws {
        let url = URL(string: "https://example.com/recipe")!
        let html = """
        <html><head><title>Reader Soup</title></head><body>
        <h1>Reader Soup</h1>
        <h2>Ingredients</h2>
        <ul><li>2 cups stock</li><li>1 onion</li></ul>
        <h2>Instructions</h2>
        <ol><li>Simmer the stock.</li><li>Add the onion.</li></ol>
        </body></html>
        """
        StubURLProtocol.handler = { request in
            (self.response(request.url!), Data(html.utf8))
        }
        let extraction = try await WebsiteRecipeExtractor.extract(
            url: url,
            sourceType: .website,
            fetcher: WebsiteFetcher(session: session)
        )
        XCTAssertEqual(extraction.method, .pageHeuristics)
        XCTAssertEqual(extraction.drafts.first?.title, "Reader Soup")
        XCTAssertEqual(extraction.drafts.first?.ingredients.count, 2)
        XCTAssertEqual(extraction.drafts.first?.instructions.count, 2)
        XCTAssertFalse(extraction.foundStructuredData)
    }
}
