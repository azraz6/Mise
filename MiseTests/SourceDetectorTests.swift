import XCTest
@testable import Mise

final class SourceDetectorTests: XCTestCase {
    func testAcceptsOrdinaryRecipeURL() {
        let result = SourceDetector.validatedURL(from: "https://smittenkitchen.com/2024/05/lemon-pasta/?utm_source=test")
        guard case .success(let url) = result else {
            return XCTFail("Expected a valid URL, got \(result)")
        }
        XCTAssertEqual(url.host, "smittenkitchen.com")
        // `URL.path` drops a trailing slash on this SDK, so assert the exact
        // serialized address instead.
        XCTAssertEqual(url.absoluteString, "https://smittenkitchen.com/2024/05/lemon-pasta/?utm_source=test")
    }

    func testAddsHTTPSWhenSchemeIsMissing() {
        guard case .success(let url) = SourceDetector.validatedURL(from: "www.seriouseats.com/recipes/focaccia") else {
            return XCTFail("Expected a valid URL")
        }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.seriouseats.com")
    }

    func testExtractsFirstSafeURLFromSharedText() {
        let text = """
        This looks delicious http://127.0.0.1/private and also https://www.kingarthurbaking.com/recipes/bread
        """
        let url = SourceDetector.firstWebURL(in: text)
        XCTAssertEqual(url?.host, "www.kingarthurbaking.com")
    }

    func testRejectsEmptyInput() {
        XCTAssertEqual(SourceDetector.validatedURL(from: "   "), .failure(.empty))
    }

    func testRejectsUnsupportedSchemes() {
        XCTAssertEqual(SourceDetector.validatedURL(from: "file:///etc/passwd"), .failure(.unsupportedScheme))
        XCTAssertEqual(SourceDetector.validatedURL(from: "javascript:alert(1)"), .failure(.unsupportedScheme))
        XCTAssertEqual(SourceDetector.validatedURL(from: "mailto:hello@example.com"), .failure(.unsupportedScheme))
    }

    func testRejectsCredentialedURLs() {
        guard case .failure(let error) = SourceDetector.validatedURL(from: "https://user:secret@example.com/recipe") else {
            return XCTFail("Credentialed URLs must not be imported")
        }
        XCTAssertEqual(error, .invalidURL)
    }

    func testRejectsLocalAndPrivateHosts() {
        let unsafe = [
            "http://localhost/recipe",
            "http://localhost.localdomain/recipe",
            "http://printer.local/recipe",
            "http://router.internal/recipe",
            "http://127.0.0.1/recipe",
            "http://10.0.0.5/recipe",
            "http://172.16.4.2/recipe",
            "http://192.168.1.9/recipe",
            "http://169.254.1.1/recipe",
            "http://0.0.0.0/recipe",
            "http://2130706433/recipe",
            "http://0x7f000001/recipe",
            "http://[::1]/recipe",
            "http://[fe80::1]/recipe",
            "http://intranet/recipe",
            "http://recipes.test/recipe"
        ]
        for raw in unsafe {
            guard case .failure(let error) = SourceDetector.validatedURL(from: raw) else {
                XCTFail("Expected \(raw) to be rejected")
                continue
            }
            XCTAssertEqual(error, .unsafeAddress, "Unexpected error for \(raw)")
        }
    }

    func testAllowsPublicDomainThatLooksNumeric() {
        guard case .success(let url) = SourceDetector.validatedURL(from: "https://123kitchen.com/recipe") else {
            return XCTFail("Expected public domain to pass")
        }
        XCTAssertEqual(url.host, "123kitchen.com")
    }

    func testSafeRemoteURLChecksSchemeHostAndCredentials() {
        XCTAssertTrue(SourceDetector.isSafeRemoteURL(URL(string: "https://example.com/recipe")!))
        XCTAssertFalse(SourceDetector.isSafeRemoteURL(URL(string: "ftp://example.com/recipe")!))
        XCTAssertFalse(SourceDetector.isSafeRemoteURL(URL(string: "https://localhost/recipe")!))
        XCTAssertFalse(SourceDetector.isSafeRemoteURL(URL(string: "https://user:pass@example.com/recipe")!))
    }

    func testClassifiesSupportedSources() {
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://www.instagram.com/p/abc/")!), .instagram)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://vm.tiktok.com/ZMabc/")!), .tiktok)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://youtu.be/abc123XYZ")!), .youtube)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://www.facebook.com/reel/123")!), .facebook)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://www.pinterest.co.uk/pin/123/")!), .pinterest)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://smittenkitchen.com/recipe")!), .website)
    }

    func testLookalikeDomainsAreNotSocialSources() {
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://notinstagram.com/recipe")!), .website)
        XCTAssertEqual(SourceDetector.classify(URL(string: "https://youtube.example.com/recipe")!), .website)
    }

    func testYouTubeVideoIDExtraction() {
        XCTAssertEqual(SourceDetector.youtubeVideoID(from: URL(string: "https://youtu.be/dQw4w9WgXcQ")!), "dQw4w9WgXcQ")
        XCTAssertEqual(SourceDetector.youtubeVideoID(from: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!), "dQw4w9WgXcQ")
        XCTAssertEqual(SourceDetector.youtubeVideoID(from: URL(string: "https://www.youtube.com/shorts/abc123XYZ")!), "abc123XYZ")
        XCTAssertNil(SourceDetector.youtubeVideoID(from: URL(string: "https://www.youtube.com/watch?v=short")!))
    }

    func testNormalizationRemovesTrackingAndDecoration() {
        let url = URL(string: "https://WWW.Example.com/Recipe/?utm_source=newsletter&fbclid=abc&id=42#steps")!
        let normalized = SourceDetector.normalizedURLString(url)
        XCTAssertEqual(normalized, "https://example.com/recipe?id=42")
    }

    func testNormalizationCollapsesTrailingSlash() {
        let url = URL(string: "https://example.com/recipe///")!
        XCTAssertEqual(SourceDetector.normalizedURLString(url), "https://example.com/recipe")
    }
}
