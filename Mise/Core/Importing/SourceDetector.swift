import Foundation

enum ImportInputError: LocalizedError, Equatable {
    case empty
    case invalidURL
    case unsupportedScheme
    case unsafeAddress
    case notHTTP

    var errorDescription: String? {
        switch self {
        case .empty:
            return "There’s nothing to import yet."
        case .invalidURL:
            return "That doesn’t look like a web address."
        case .unsupportedScheme:
            return "Only http and https links can be imported."
        case .unsafeAddress:
            return "Local addresses and private network links can’t be imported."
        case .notHTTP:
            return "Only ordinary web pages can be imported."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .empty:
            return "Paste a recipe link, caption, or select a screenshot."
        case .invalidURL, .notHTTP:
            return "Check the address and try again, or paste the recipe text instead."
        case .unsupportedScheme:
            return "Open the page in your browser, then share the https link into Mise."
        case .unsafeAddress:
            return "Mise only reads public http and https pages."
        }
    }
}

enum SourceDetector {
    static func validatedURL(from rawInput: String) -> Result<URL, ImportInputError> {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        // A string with an explicit scheme is validated as one address, even if
        // the scheme is unsupported. This preserves useful errors for file:,
        // javascript:, and mailto: input instead of treating it as page text.
        if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil {
            return validatedComponents(from: trimmed)
        }

        // A bare domain or domain/path typed by hand is assumed to be https.
        if !trimmed.contains(where: { $0.isWhitespace }) {
            return validatedComponents(from: "https://" + trimmed)
        }

        // Otherwise treat the input as shared text and take the first safe link.
        if let extracted = firstWebURL(in: trimmed) {
            return .success(extracted)
        }
        return .failure(.invalidURL)
    }

    private static func validatedComponents(from raw: String) -> Result<URL, ImportInputError> {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased() else {
            return .failure(.invalidURL)
        }
        guard scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = components.host, !host.isEmpty else {
            return .failure(.invalidURL)
        }
        guard components.user == nil, components.password == nil else {
            return .failure(.invalidURL)
        }
        // Check private/reserved/IP-literal hosts before generic shape checks so
        // the user gets the accurate “unsafe address” message.
        guard !isUnsafeHost(host) else { return .failure(.unsafeAddress) }
        guard host.contains("."), let url = components.url else { return .failure(.invalidURL) }
        return .success(url)
    }

    /// Returns true when a URL is an ordinary, public http(s) address that the
    /// importer is allowed to contact. Mise never fetches local, private,
    /// link-local, or IP-literal hosts.
    static func isSafeRemoteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host, !host.isEmpty else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil else {
            return false
        }
        return !isUnsafeHost(host)
    }

    static func firstWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            guard isSafeRemoteURL(url) else { continue }
            return url
        }
        return nil
    }

    static func classify(_ url: URL) -> RecipeSourceType {
        guard let host = url.host?.lowercased() else { return .website }
        if matches(host: host, domain: "instagram.com") || matches(host: host, domain: "instagr.am") {
            return .instagram
        }
        if matches(host: host, domain: "tiktok.com") || matches(host: host, domain: "vm.tiktok.com") {
            return .tiktok
        }
        if matches(host: host, domain: "youtube.com") || matches(host: host, domain: "youtu.be") {
            return .youtube
        }
        if matches(host: host, domain: "facebook.com") || matches(host: host, domain: "fb.watch") {
            return .facebook
        }
        if host.contains("pinterest.") || matches(host: host, domain: "pin.it") {
            return .pinterest
        }
        return .website
    }

    static func youtubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if matches(host: host, domain: "youtu.be") {
            let id = url.pathComponents.dropFirst().first
            return id.flatMap(validYouTubeID)
        }
        if matches(host: host, domain: "youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return validYouTubeID(id)
            }
            let parts = url.pathComponents
            if parts.count >= 3, ["shorts", "embed", "live"].contains(parts[1]) {
                return validYouTubeID(parts[2])
            }
        }
        return nil
    }

    static func normalizedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        var host = components.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { host = String(host.dropFirst(2)) }
        components.host = host
        components.fragment = nil
        let filteredQuery = components.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_")
                && !["fbclid", "gclid", "igshid", "si", "mc_cid", "mc_eid"].contains(name)
        }
        components.queryItems = (filteredQuery?.isEmpty == true) ? nil : filteredQuery
        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        components.path = path
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func validYouTubeID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard trimmed.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    static func isUnsafeHost(_ host: String?) -> Bool {
        guard var host = host?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else { return true }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        while host.hasSuffix("."), host.count > 1 { host.removeLast() }

        // IPv6 and any other colon-containing literal.
        if host.contains(":") { return true }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }

        let blockedSuffixes = [
            "local", "localdomain", "internal", "home", "lan", "intranet", "corp", "private",
            "test", "invalid", "example", "onion"
        ]
        for suffix in blockedSuffixes where host == suffix || host.hasSuffix("." + suffix) {
            return true
        }

        // Require an ordinary multi-label DNS name.
        guard host.contains(".") else { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return true }

        // Reject IP literals, including integer, octal, and hex encodings.
        if host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil { return true }
        if labels.contains(where: { $0.hasPrefix("0x") }) { return true }
        return false
    }
}
