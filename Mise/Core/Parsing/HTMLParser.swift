import Foundation

enum HTMLText {
    static func decodeEntities(_ string: String) -> String {
        var result = string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&rsquo;", with: "’")
            .replacingOccurrences(of: "&lsquo;", with: "‘")
            .replacingOccurrences(of: "&ldquo;", with: "“")
            .replacingOccurrences(of: "&rdquo;", with: "”")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&deg;", with: "°")
            .replacingOccurrences(of: "&frac12;", with: "½")
            .replacingOccurrences(of: "&frac14;", with: "¼")
            .replacingOccurrences(of: "&frac34;", with: "¾")

        if let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let token = ns.substring(with: match.range(at: 1))
                let value: UInt32?
                if token.lowercased().hasPrefix("x") {
                    value = UInt32(token.dropFirst(), radix: 16)
                } else {
                    value = UInt32(token)
                }
                guard let value, let scalar = UnicodeScalar(value) else { continue }
                result = (result as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        return result
    }

    static func stripTags(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "(?is)<script.*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<li[^>]*>", with: "- ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "[\\t\\u{00A0}]", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func readableText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "(?is)<script.*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style.*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<noscript.*?</noscript>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<svg.*?</svg>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<template.*?</template>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<h[1-6][^>]*>", with: "\n## ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</h[1-6]>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n- ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</(p|div|section|article|tr|ul|ol)>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line -> String in
            line.replacingOccurrences(of: "[\\t\\u{00A0}]", with: " ", options: .regularExpression)
                .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var collapsed: [String] = []
        var lastWasBlank = false
        for line in lines {
            if line.isEmpty {
                if !lastWasBlank { collapsed.append("") }
                lastWasBlank = true
            } else {
                collapsed.append(line)
                lastWasBlank = false
            }
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func jsonLDScripts(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        ) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            var body = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            body = body.replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return body
        }
    }
}

struct PageMetadata: Equatable {
    var title: String
    var description: String
    var imageURLString: String?
    var siteName: String
}

enum PageMetadataParser {
    static func parse(html: String, baseURL: URL) -> PageMetadata {
        let metaTags = metaTagAttributes(in: html)
        var properties: [String: String] = [:]
        for attributes in metaTags {
            let key = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
            guard !key.isEmpty, let content = attributes["content"], !content.isEmpty else { continue }
            if properties[key] == nil { properties[key] = HTMLText.decodeEntities(content) }
        }
        let ogTitle = properties["og:title"] ?? properties["twitter:title"] ?? ""
        let documentTitle = firstMatch(#"(?is)<title[^>]*>(.*?)</title>"#, in: html)
            .map { HTMLText.stripTags($0) } ?? ""
        let h1 = firstMatch(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html)
            .map { HTMLText.stripTags($0) } ?? ""
        let title = [ogTitle, h1, documentTitle].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = (properties["og:description"] ?? properties["twitter:description"] ?? properties["description"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var image = properties["og:image"] ?? properties["twitter:image"] ?? ""
        if image.isEmpty {
            image = firstMatch(#"(?is)<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']"#, in: html) ?? ""
        }
        let resolvedImage = resolveURL(image, baseURL: baseURL)
        return PageMetadata(
            title: title,
            description: description,
            imageURLString: resolvedImage,
            siteName: properties["og:site_name"] ?? baseURL.host ?? ""
        )
    }

    static func resolveURL(_ raw: String, baseURL: URL) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            return url.absoluteString
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private static func metaTagAttributes(in html: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<meta\s+[^>]*>"#) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { match in
            let tag = ns.substring(with: match.range)
            return attributeMap(in: tag)
        }
    }

    private static func attributeMap(in tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*["']([^"']*)["']"#) else {
            return [:]
        }
        let ns = tag as NSString
        var map: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges >= 3 {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let value = ns.substring(with: match.range(at: 2))
            if map[key] == nil { map[key] = value }
        }
        return map
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
