import Foundation

struct FetchedPage {
    var requestedURL: URL
    var finalURL: URL
    var html: String
    var contentType: String
}

protocol PageFetching {
    func fetch(_ url: URL) async throws -> FetchedPage
}

final class SafeRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var blockedURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, SourceDetector.isSafeRemoteURL(url) else {
            blockedURL = request.url
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class WebsiteFetcher: PageFetching {
    static let maximumBytes = 8 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = [
                "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
                "Accept-Language": "en-US,en;q=0.8",
                "User-Agent": "Mise/1.0 (iPhone; recipe importer)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        guard SourceDetector.isSafeRemoteURL(url) else {
            throw ImportFailure.invalidInput(.unsafeAddress)
        }

        var currentURL = url
        var redirectCount = 0

        while true {
            try Task.checkCancellation()

            var request = URLRequest(url: currentURL)
            request.timeoutInterval = 25
            request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
            request.setValue("Mise/1.0 (iPhone; recipe importer)", forHTTPHeaderField: "User-Agent")

            let redirects = SafeRedirectDelegate()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request, delegate: redirects)
            } catch let error as URLError {
                switch error.code {
                case .cancelled:
                    throw ImportFailure.cancelled
                case .timedOut:
                    throw ImportFailure.timedOut
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
                    throw ImportFailure.offline
                default:
                    throw ImportFailure.unreadablePage
                }
            } catch is CancellationError {
                throw ImportFailure.cancelled
            } catch {
                throw ImportFailure.unreadablePage
            }

            if redirects.blockedURL != nil {
                throw ImportFailure.invalidInput(.unsafeAddress)
            }
            guard let http = response as? HTTPURLResponse else {
                throw ImportFailure.unreadablePage
            }

            // URLSession normally follows redirects before returning, but a
            // response can still arrive as a redirect (for example from a
            // protocol handler or a server that omits delegate handling).
            // Follow it explicitly so every hop is validated and testable.
            if [301, 302, 303, 307, 308].contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: http.url ?? currentURL)?.absoluteURL {
                guard SourceDetector.isSafeRemoteURL(next) else {
                    throw ImportFailure.invalidInput(.unsafeAddress)
                }
                redirectCount += 1
                guard redirectCount <= 5 else { throw ImportFailure.unreadablePage }
                currentURL = next
                continue
            }

            if let finalURL = http.url, !SourceDetector.isSafeRemoteURL(finalURL) {
                throw ImportFailure.invalidInput(.unsafeAddress)
            }
            guard (200...299).contains(http.statusCode) else {
                throw ImportFailure.httpStatus(http.statusCode)
            }
            if let expected = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init), expected > Int64(Self.maximumBytes) {
                throw ImportFailure.responseTooLarge
            }
            guard data.count <= Self.maximumBytes else {
                throw ImportFailure.responseTooLarge
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            let mime = contentType.split(separator: ";").first.map(String.init)?.lowercased() ?? ""
            let allowed = ["text/html", "application/xhtml+xml", "text/plain", ""]
            guard allowed.contains(mime) else {
                throw ImportFailure.unsupportedContent(mime.isEmpty ? nil : mime)
            }
            guard let html = Self.decode(data: data, contentType: contentType), !html.isEmpty else {
                throw ImportFailure.unreadablePage
            }
            let finalURL = http.url ?? currentURL
            return FetchedPage(requestedURL: url, finalURL: finalURL, html: html, contentType: contentType)
        }
    }

    static func decode(data: Data, contentType: String) -> String? {
        if let range = contentType.range(of: #"charset\s*=\s*["']?([^;"'\s]+)"#, options: [.regularExpression, .caseInsensitive]),
           let charsetRange = contentType.range(of: "=", range: range).map({ contentType[$0.upperBound...] }) {
            let charset = String(charsetRange).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            let encoding = Self.encoding(for: charset)
            if let encoding, let string = String(data: data, encoding: encoding) { return string }
        }
        if let string = String(data: data, encoding: .utf8) { return string }
        if let string = String(data: data, encoding: .windowsCP1252) { return string }
        if let string = String(data: data, encoding: .isoLatin1) { return string }
        return nil
    }

    private static func encoding(for charset: String) -> String.Encoding? {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16", "utf16": return .utf16
        default: return nil
        }
    }
}

enum WebsiteRecipeExtractor {
    static func extract(
        url: URL,
        sourceType: RecipeSourceType,
        fetcher: PageFetching = WebsiteFetcher()
    ) async throws -> PageExtraction {
        let page = try await fetcher.fetch(url)
        try Task.checkCancellation()
        let metadata = PageMetadataParser.parse(html: page.html, baseURL: page.finalURL)
        var warnings: [String] = []

        let structured = JSONLDExtractor.parse(
            html: page.html,
            sourceURL: url,
            sourceTitle: metadata.title.isEmpty ? (url.host ?? "Recipe") : metadata.title,
            sourceType: sourceType,
            pageImageURL: metadata.imageURLString
        )
        warnings.append(contentsOf: structured.warnings)
        let usableStructured = structured.drafts.filter {
            !$0.ingredients.isEmpty || !$0.instructions.isEmpty
        }
        if !usableStructured.isEmpty {
            if page.finalURL.absoluteString != url.absoluteString {
                warnings.append("The page redirected to \(page.finalURL.host ?? "another address").")
            }
            return PageExtraction(
                drafts: usableStructured,
                pageTitle: metadata.title.isEmpty ? page.finalURL.host ?? "Recipe" : metadata.title,
                pageDescription: metadata.description,
                imageURLString: metadata.imageURLString,
                method: .jsonLD,
                warnings: Array(NSOrderedSet(array: warnings).compactMap { $0 as? String }),
                foundStructuredData: true
            )
        }

        let readable = HTMLText.readableText(page.html)
        guard !readable.isEmpty else { throw ImportFailure.unreadablePage }
        let heuristic = TextRecipeParser.parse(
            readable,
            sourceType: sourceType,
            sourceURL: url,
            sourceTitle: metadata.title,
            method: .pageHeuristics
        )
        var draft = heuristic.draft
        if draft.ingredients.isEmpty || draft.instructions.isEmpty {
            return PageExtraction(
                drafts: [],
                pageTitle: metadata.title.isEmpty ? (page.finalURL.host ?? "Recipe") : metadata.title,
                pageDescription: metadata.description,
                imageURLString: metadata.imageURLString,
                method: .pageHeuristics,
                warnings: Array(NSOrderedSet(array: warnings).compactMap { $0 as? String }),
                foundStructuredData: false
            )
        }

        let pageTitle = metadata.title.isEmpty ? draft.title : metadata.title
        draft.title = pageTitle
        draft.sourceTitle = pageTitle
        draft.coverImageRemoteURL = metadata.imageURLString
        draft.summary = draft.summary.isEmpty ? metadata.description : draft.summary
        draft.confidence = .heuristic
        draft.extractionMethod = .pageHeuristics
        draft.warnings = Array(NSOrderedSet(array: [
            "No structured recipe data was found. Mise read the visible page text and flagged it for review."
        ] + heuristic.warnings).compactMap { $0 as? String })
        warnings.append(contentsOf: draft.warnings)
        return PageExtraction(
            drafts: [draft],
            pageTitle: pageTitle,
            pageDescription: metadata.description,
            imageURLString: metadata.imageURLString,
            method: .pageHeuristics,
            warnings: Array(NSOrderedSet(array: warnings).compactMap { $0 as? String }),
            foundStructuredData: false
        )
    }
}
