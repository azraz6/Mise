import Foundation

struct SocialLinkMetadata {
    var title: String
    var author: String
}

enum SocialLinkMetadataService {
    static func metadata(for url: URL, sourceType: RecipeSourceType) async -> SocialLinkMetadata? {
        switch sourceType {
        case .youtube:
            return await fetchOEmbed(
                endpoint: "https://www.youtube.com/oembed",
                url: url
            )
        case .tiktok:
            return await fetchOEmbed(
                endpoint: "https://www.tiktok.com/oembed",
                url: url
            )
        default:
            return nil
        }
    }

    private static func fetchOEmbed(endpoint: String, url: URL) async -> SocialLinkMetadata? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let endpointURL = components.url else { return nil }
        var request = URLRequest(url: endpointURL)
        request.timeoutInterval = 10
        request.setValue("Mise/1.0 (iPhone)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  data.count <= 512 * 1024,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let author = (object["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            return SocialLinkMetadata(title: title, author: author)
        } catch {
            return nil
        }
    }
}
